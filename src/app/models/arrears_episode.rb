# Episódio de atraso de um contrato ou de um cliente (21, R434; 13, revisão 7, `dias em cobrança`; plano técnico da camada 23, decisão 1).
#
# O início vem dos títulos: cada título esteve vencido do dia seguinte ao vencimento (ou do dia em que voltou a ser cobrado, `reopened_on`) até o
# dia em que saiu de cobrança (`closed_on`; sem ele, até hoje). Os intervalos que se tocam formam uma ilha; a ilha que contém hoje é o atraso em
# curso. O episódio é guardado para a chave ficar estável: uma correção de carga que adianta um vencimento não abre outro episódio; só um dia
# sem atraso no meio (uma ilha que acabou depois do início do episódio) abre outro.
#
# `refresh` roda antes de cada rodada da régua, no "ainda vale?", na conferência e na tarefa diária dos segmentos. A tarefa diária é o que vê
# "pagou na segunda, estornado na terça" mesmo sem rodada no meio: ela fecha o episódio no dia sem atraso, e o estorno abre outro (Q6). O estorno
# no mesmo dia do pagamento não deixa dia sem atraso e continua o episódio (decisão 3).
class ArrearsEpisode < ApplicationRecord
  include TenantScoped

  SUBJECTS = %w[contracts customers].freeze
  LOCK = 8

  validates :subject_type, inclusion: { in: SUBJECTS }

  scope :open, -> { where(ended_on: nil) }

  # Atualiza os episódios do credor para o sujeito (`contracts` ou `customers`); `only`: ids do sujeito, para refazer só esses. Devolve
  # { opened:, closed:, reopened: }. SQL de conjunto, como os recálculos dos segmentos (decisão 0021): o episódio é derivado dos títulos.
  def self.refresh(tenant, subject, only: nil, today: Date.current)
    subject = subject.to_s
    raise ArgumentError, "sujeito desconhecido: #{subject}" unless SUBJECTS.include?(subject)
    return { opened: 0, closed: 0, reopened: 0 } if only && only.empty?

    Operations::Context.system do
      transaction do
        Portfolio::Sql.execute("select pg_advisory_xact_lock(?, ?)", LOCK, tenant.id)
        Refresh.new(tenant.id.to_i, subject, only&.map { |id| Integer(id) }, today).call
      end
    end
  end

  # A passada diária, registrada por credor (O8); a falha fica no registro e não para o resto da tarefa dos segmentos (MT-19).
  def self.daily(tenant, today: Date.current)
    run = TaskRun.create!(tenant: tenant, name: "arrears_episodes", started_at: Time.current)
    counts = SUBJECTS.map { |subject| refresh(tenant, subject, today: today) }
    run.update!(status: :succeeded, finished_at: Time.current, processed: counts.sum { |count| count.values.sum })
    run
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { tenant_id: tenant.id })
    run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
    run
  end

  # O início do episódio em curso de cada sujeito (para `dias em cobrança`): { id => data }.
  def self.started_on_of(tenant, subject, ids)
    open.where(tenant_id: tenant.id, subject_type: subject.to_s, subject_id: ids).pluck(:subject_id, :started_on).to_h
  end

  class Refresh
    def initialize(tenant_id, subject, only, today)
      @t = tenant_id
      @subject = subject
      @only = only
      @today = "#{ActiveRecord::Base.connection.quote(today)}::date"
      @quoted = ActiveRecord::Base.connection.quote(subject)
    end

    def call
      Portfolio::Sql.execute("drop table if exists episode_calc")
      Portfolio::Sql.execute("create temporary table episode_calc (sid bigint primary key, cur_start date, prev_end date, last_close date) on commit drop")
      Portfolio::Sql.execute("insert into episode_calc #{islands_sql}")
      closed = close_finished
      reopened = reopen_contiguous
      opened = open_new
      Portfolio::Sql.execute("drop table episode_calc")
      { opened: opened, closed: closed, reopened: reopened }
    end

    # Os intervalos vencidos de cada título, unidos em ilhas por sujeito: a ilha que contém hoje (`cur_start`), o fim da última ilha que já
    # acabou (`prev_end`, o dia em que deixou de estar vencido) e a última saída de cobrança de qualquer título (`last_close`), que dá o fim do
    # episódio quando o título foi pago no mesmo dia em que venceu e não deixou intervalo.
    def islands_sql
      today = @today
      <<~SQL
        with iv as (#{intervals_sql}),
        ord as (
          select sid, s, e, max(e) over (partition by sid order by s, e rows between unbounded preceding and 1 preceding) as prev_max
            from iv where s < e
        ),
        grp as (
          select sid, s, e, sum(case when prev_max is null or s > prev_max then 1 else 0 end) over (partition by sid order by s, e) as g from ord
        ),
        isl as (select sid, min(s) as s, max(e) as e from grp group by sid, g),
        closes as (select sid, max(e) as last_close from iv where e <= #{today} group by sid)
        select coalesce(i.sid, k.sid), i.cur_start, i.prev_end, k.last_close
          from (select sid, max(s) filter (where e > #{today}) as cur_start, max(e) filter (where e <= #{today}) as prev_end from isl group by sid) i
          full join closes k on k.sid = i.sid
      SQL
    end

    def intervals_sql
      span = "greatest(b.due_date + 1, coalesce(b.reopened_on, b.due_date + 1)) as s, coalesce(b.closed_on, #{@today} + 1) as e"
      kept = "b.tenant_id = #{@t} and (b.status = 'active' or b.closed_on is not null)"
      if @subject == "contracts"
        "select b.contract_id as sid, #{span} from bills b where #{kept}#{" and b.contract_id = any(#{ids})" if @only}"
      else
        "select cc.customer_id as sid, #{span} from bills b join contract_customers cc on cc.contract_id = b.contract_id " \
          "where #{kept}#{" and cc.customer_id = any(#{ids})" if @only}"
      end
    end

    # O aberto termina quando não há mais atraso, ou quando uma ilha acabou depois do início dele (houve dia sem atraso, e o atraso de hoje é outro).
    def close_finished
      Portfolio::Sql.run(<<~SQL)
        update arrears_episodes e set ended_on = greatest(coalesce(c.prev_end, c.last_close, #{@today}) - 1, e.started_on - 1), updated_at = now()
          from arrears_episodes o left join episode_calc c on c.sid = o.subject_id
         where e.id = o.id and #{open_scope('o')}
           and (c.cur_start is null or (c.cur_start > o.started_on and c.prev_end > o.started_on))
      SQL
    end

    # Sem episódio aberto e com atraso que encosta no fim do último episódio (o estorno no mesmo dia do pagamento, visto por uma rodada no meio):
    # o último volta a valer.
    def reopen_contiguous
      Portfolio::Sql.run(<<~SQL)
        update arrears_episodes e set ended_on = null, updated_at = now()
          from (
            select distinct on (l.subject_id) l.id, l.ended_on, c.cur_start
              from episode_calc c join arrears_episodes l on l.tenant_id = #{@t} and l.subject_type = #{@quoted} and l.subject_id = c.sid
             where c.cur_start is not null
               and not exists (select 1 from arrears_episodes a where a.tenant_id = #{@t} and a.subject_type = #{@quoted} and a.subject_id = c.sid and a.ended_on is null)
             order by l.subject_id, l.started_on desc, l.id desc
          ) last
         where e.id = last.id and last.cur_start <= last.ended_on + 1
      SQL
    end

    def open_new
      Portfolio::Sql.run(<<~SQL)
        insert into arrears_episodes (tenant_id, subject_type, subject_id, started_on, created_at, updated_at)
        select #{@t}, #{@quoted}, c.sid, c.cur_start, now(), now() from episode_calc c
         where c.cur_start is not null
           and not exists (select 1 from arrears_episodes a where a.tenant_id = #{@t} and a.subject_type = #{@quoted} and a.subject_id = c.sid and a.ended_on is null)
      SQL
    end

    private
      def ids = "'{#{@only.join(',')}}'::bigint[]"

      def open_scope(alias_name)
        "#{alias_name}.tenant_id = #{@t} and #{alias_name}.subject_type = #{@quoted} and #{alias_name}.ended_on is null" \
          "#{" and #{alias_name}.subject_id = any(#{ids})" if @only}"
      end
  end
  private_constant :Refresh
end
