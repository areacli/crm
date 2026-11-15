module Cadences
  # A decisão de uma rodada (21, R429 a R436; plano técnico da camada 23, "Rodada", etapa "decidir"). Para a régua, com os segmentos como estão:
  # põe cada sujeito na primeira raia que o enquadra, acha o objeto e o momento pelo marco, a última coluna alcançada e, se ela ainda não disparou
  # no episódio, grava uma decisão por ação da célula; as colunas com ação que ficaram para trás sem disparar ficam como puladas. Grava antes da
  # fila; a retomada não refaz a régua já decidida. SQL de conjunto, como os recálculos dos segmentos (decisão 0021): a decisão é derivada.
  #
  # `simulate: true` (conferência, R442; "ainda vale?", R438) calcula em tabelas temporárias e devolve as contagens, sem gravar decisão nem
  # pulada. `only_ids` restringe aos sujeitos dados; `day` troca o dia (o "ainda vale?" olha hoje); `refresh` refaz o episódio antes (o "ainda
  # vale?" refaz o dos sujeitos dele; a conferência não mexe na tabela).
  class Decision
    Result = Data.define(:summary, :lane_error)

    EPISODE_MILESTONES = %w[contract_arrears customer_arrears contract_in_collection customer_in_collection].freeze

    def initialize(round, simulate: false, only_ids: nil, day: nil, refresh: nil)
      @round = round
      @cadence = round.cadence
      @tenant = round.tenant
      @simulate = simulate
      @only_ids = only_ids
      @day = day || round.day
      @refresh = refresh.nil? ? !simulate : refresh
      @connection = ActiveRecord::Base.connection
    end

    def call
      prepare_episodes
      lane_error = classify
      objects
      reached
      summary = counts.merge("lane_error" => lane_error)
      unless @simulate
        write_decisions
        write_skips
      end
      Result.new(summary: summary, lane_error: lane_error)
    end

    private
      def t = @tenant.id.to_i
      def c = @cadence.id.to_i
      def today = "#{@connection.quote(@day)}::date"
      def subject = @cadence.subject
      def execute(sql) = Portfolio::Sql.execute(sql)
      def run(sql) = Portfolio::Sql.run(sql)

      # O episódio de atraso do sujeito antes de ler o marco (R434: calculado dos dados). Na conferência, a tabela não muda: vale a última passada.
      def prepare_episodes
        return if !@refresh || !EPISODE_MILESTONES.include?(@cadence.milestone)

        ArrearsEpisode.refresh(@tenant, subject, only: @only_ids, today: @day)
      end

      # Raias (R431): o primeiro segmento que casa; o sujeito que não casa fica na trilha padrão. Raia com segmento desativado ou inválido é erro: ela e
      # as de baixo saem da conta, e quem não coube nas de cima não recebe nada nesta rodada (21, "Casos de exceção").
      def classify
        lanes = @cadence.lanes.includes(:segment).to_a
        entries = []
        error = nil
        default_id = lanes.find(&:default?).id
        lanes.reject(&:default?).each do |lane|
          expression = lane.segment&.expression_object
          if lane.segment.nil? || !lane.segment.active? || !expression.valid?
            error = { "lane_id" => lane.id, "position" => lane.position, "reason" => lane.segment&.active? == false ? "segmento desativado" : "segmento inválido" }
            default_id = 0
            break
          end
          entries << [ lane.id, expression ]
        end
        query = Segments::Compiler.new(@tenant, today: @day).classify_subjects(subject, entries, default_id: default_id, only_ids: @only_ids)
        execute("drop table if exists cadence_lane_calc")
        execute("create temporary table cadence_lane_calc (subject_id bigint primary key, lane_id bigint) on commit drop")
        @connection.exec_query("insert into cadence_lane_calc select subject_id, item_id from (#{query.sql}) q", "Cadences", query.binds)
        error
      end

      # O objeto e o momento de cada sujeito pelo marco (R429). `state`: ok, out (fora do episódio) ou none (sem marco).
      def objects
        execute("drop table if exists cadence_obj")
        execute(<<~SQL)
          create temporary table cadence_obj (subject_id bigint, object_key text, episode_key text, contract_id bigint, customer_id bigint, bill_id bigint,
                                              moment integer, state text) on commit drop
        SQL
        execute("insert into cadence_obj #{objects_sql}")
      end

      def objects_sql
        case @cadence.milestone
        when "bill_due"
          <<~SQL
            select l.subject_id, 'b' || b.id, 'b' || b.id || ':' || coalesce(b.reopened_on, #{BrDate.sql_date('b.created_at')}), b.contract_id, null::bigint, b.id,
                   #{today} - b.due_date, 'ok'
              from cadence_lane_calc l join bills b on b.contract_id = l.subject_id and b.tenant_id = #{t} and b.status = 'active'
            union all
            select l.subject_id, null, null, l.subject_id, null, null, null, 'out' from cadence_lane_calc l
             where not exists (select 1 from bills b where b.contract_id = l.subject_id and b.tenant_id = #{t} and b.status = 'active')
          SQL
        when "contract_arrears", "contract_in_collection"
          moment = @cadence.milestone == "contract_arrears" ? "od.days" : "#{today} - e.started_on"
          <<~SQL
            select l.subject_id, 'c' || l.subject_id, 'e' || e.id, l.subject_id, null::bigint, null::bigint,
                   case when e.id is null then null else #{moment} end, case when e.id is null then 'out' else 'ok' end
              from cadence_lane_calc l
              left join arrears_episodes e on e.tenant_id = #{t} and e.subject_type = 'contracts' and e.subject_id = l.subject_id and e.ended_on is null
              left join (select contract_id, max(#{today} - due_date) as days from bills where tenant_id = #{t} and status = 'active' and due_date < #{today} group by 1) od
                on od.contract_id = l.subject_id
          SQL
        when "customer_arrears", "customer_in_collection"
          moment = @cadence.milestone == "customer_arrears" ? "od.days" : "#{today} - e.started_on"
          <<~SQL
            select l.subject_id, 'u' || l.subject_id, 'e' || e.id, null::bigint, l.subject_id, null::bigint,
                   case when e.id is null then null else #{moment} end, case when e.id is null then 'out' else 'ok' end
              from cadence_lane_calc l
              left join arrears_episodes e on e.tenant_id = #{t} and e.subject_type = 'customers' and e.subject_id = l.subject_id and e.ended_on is null
              left join (select cc.customer_id, max(#{today} - b.due_date) as days from bills b join contract_customers cc on cc.contract_id = b.contract_id
                          where b.tenant_id = #{t} and b.status = 'active' and b.due_date < #{today} group by 1) od on od.customer_id = l.subject_id
          SQL
        when "contract_start"
          <<~SQL
            select l.subject_id, 'c' || l.subject_id, 's' || k.started_on, l.subject_id, null::bigint, null::bigint, #{today} - k.started_on,
                   case when k.started_on is null then 'none' else 'ok' end
              from cadence_lane_calc l join contracts k on k.id = l.subject_id
          SQL
        when "contract_creation"
          date = BrDate.sql_date("k.created_at")
          "select l.subject_id, 'c' || l.subject_id, 'n' || #{date}, l.subject_id, null::bigint, null::bigint, #{today} - #{date}, 'ok' " \
            "from cadence_lane_calc l join contracts k on k.id = l.subject_id"
        when "customer_registration"
          date = BrDate.sql_date("u.created_at")
          "select l.subject_id, 'u' || l.subject_id, 'n' || #{date}, null::bigint, l.subject_id, null::bigint, #{today} - #{date}, 'ok' " \
            "from cadence_lane_calc l join customers u on u.id = l.subject_id"
        end
      end

      # A última coluna alcançada de cada objeto (momento >= coluna, R434), na raia do sujeito.
      def reached
        columns = @cadence.columns.to_a
        execute("drop table if exists cadence_reached")
        execute("create temporary table cadence_reached (object_key text, column_id bigint, offset_days integer) on commit drop")
        return if columns.empty?

        values = columns.map { |column| "(#{Integer(column.id)}, #{Integer(column.offset_days)})" }.join(", ")
        execute(<<~SQL)
          insert into cadence_reached
          select distinct on (o.object_key) o.object_key, k.id, k.off
            from cadence_obj o join (values #{values}) as k (id, off) on k.off <= o.moment
           where o.state = 'ok'
           order by o.object_key, k.off desc
        SQL
      end

      # As ações de cada célula, com a marca de parâmetro inativo (R432), como tabela de valores.
      def actions_values
        actions = @cadence.live_actions.includes(:message_piece, :queue_task, lane: :cadence).to_a
        return nil if actions.empty?

        actions.map do |action|
          "(#{Integer(action.id)}, #{Integer(action.cadence_lane_id)}, #{Integer(action.cadence_column_id)}, #{@connection.quote(action.kind)}, #{action.active_parameter? ? 'false' : 'true'})"
        end.join(", ")
      end

      def write_decisions
        values = actions_values
        return 0 unless values

        run(<<~SQL)
          insert into cadence_decisions (cadence_round_id, cadence_id, object_key, episode_key, contract_id, customer_id, bill_id, cadence_lane_id,
                                         cadence_column_id, cadence_action_id, kind, state, created_at)
          select #{Integer(@round.id)}, #{c}, o.object_key, o.episode_key, o.contract_id, o.customer_id, o.bill_id, l.lane_id, r.column_id, a.id, a.kind,
                 case when a.inactive then 'inactive_parameter' else 'decided' end, now()
            from cadence_obj o
            join cadence_lane_calc l on l.subject_id = o.subject_id
            join cadence_reached r on r.object_key = o.object_key
            join (values #{values}) as a (id, lane_id, column_id, kind, inactive) on a.lane_id = l.lane_id and a.column_id = r.column_id
           where not exists (select 1 from cadence_firings f where f.cadence_id = #{c} and f.object_key = o.object_key and f.episode_key = o.episode_key
                               and f.cadence_column_id = r.column_id)
          on conflict (cadence_round_id, cadence_action_id, object_key) do nothing
        SQL
      end

      # Colunas com ação na raia do sujeito, antes da última alcançada, que não dispararam no episódio: puladas, uma vez por episódio (R434).
      def write_skips
        values = actions_values
        return 0 unless values

        run(<<~SQL)
          insert into cadence_skips (cadence_id, object_key, episode_key, cadence_column_id, cadence_round_id, created_at)
          select distinct #{c}, o.object_key, o.episode_key, k.id, #{Integer(@round.id)}, now()
            from cadence_obj o
            join cadence_lane_calc l on l.subject_id = o.subject_id
            join cadence_reached r on r.object_key = o.object_key
            join cadence_columns k on k.cadence_id = #{c} and k.removed_at is null and k.offset_days < r.offset_days
           where exists (select 1 from (values #{values}) as a (id, lane_id, column_id, kind, inactive) where a.lane_id = l.lane_id and a.column_id = k.id)
             and not exists (select 1 from cadence_firings f where f.cadence_id = #{c} and f.object_key = o.object_key and f.episode_key = o.episode_key
                               and f.cadence_column_id = k.id)
          on conflict do nothing
        SQL
      end

      # O que só a rodada sabe e não tem linha própria (R435): avaliados, fora do episódio, sem marco, antes da primeira coluna.
      def counts
        row = Portfolio::Sql.one(<<~SQL)
          select (select count(*) from cadence_lane_calc) as evaluated,
                 (select count(distinct subject_id) from cadence_obj where state = 'out') as out_of_episode,
                 (select count(*) from cadence_obj where state = 'none') as without_milestone,
                 (select count(*) from cadence_obj o where o.state = 'ok' and not exists (select 1 from cadence_reached r where r.object_key = o.object_key)) as before_first_column
        SQL
        row.transform_values(&:to_i)
      end
  end
end
