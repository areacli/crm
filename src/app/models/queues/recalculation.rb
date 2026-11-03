module Queues
  # Recálculo do enquadramento da fila de um credor (15, R349 a R351, R355): para clientes e para contratos, o primeiro item cujo segmento casa
  # (sem regra de entrada), gravado em `queue_placements`, e a posição em cada fila pela ordem dela, por conjunto. Roda todo dia, depois de
  # cada carga e de cada mudança confirmada (completo), e depois de um acionamento ou na entrega (só os sujeitos dados, `only`).
  class Recalculation
    NAME = "queues_recalculation"

    # Critério de ordem (R355) => expressão sobre a tabela de apoio `d`; os vazios vão para o fim (no "mais tempo sem acionamento", quem
    # nunca foi acionado vem primeiro, porque é o mais tempo sem acionamento).
    ORDER_SQL = {
      "overdue_balance" => "d.overdue_balance desc nulls last",
      "overdue_days" => "d.overdue_days desc nulls last",
      "without_contact" => "d.last_contact asc nulls first",
      "return_at" => "d.return_at asc nulls last",
      "broken_promise" => "d.broken_at desc nulls last"
    }.freeze

    def initialize(tenant) = @tenant = tenant

    # Execução registrada por credor (O8); a falha de um credor fica no registro dele e não para os outros (MT-19).
    def call(today: Date.current)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      changed = apply(today: today)
      run.update!(status: :succeeded, finished_at: Time.current, processed: changed)
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    end

    # `only`: { "customers" => [ids], "contracts" => [ids] } para recalcular só esses sujeitos. Devolve quantos mudaram de fila. Quem entra
    # numa fila vai para o fim dela até o próximo recálculo completo, que refaz a posição de todos. O fim de cada fila é lido uma vez por
    # consulta (uma subconsulta por linha custava 20 s com 20 mil contratos, medição da V4).
    def apply(today: Date.current, only: nil)
      changed = 0
      Operations::Context.system do
        ApplicationRecord.transaction do
          Portfolio::Sql.execute("select pg_advisory_xact_lock(4, ?)", @tenant.id)
          Portfolio::Sql.execute("set local work_mem = '#{Segments::Compiler::WORK_MEM}'")
          WorkQueue::SUBJECTS.each do |subject|
            ids = only && Array(only[subject])
            next if only && ids.empty?

            changed += place(subject, today, ids)
          end
        end
      end
      Queues::Broadcast.changed(@tenant)
      changed
    end

    private
      def place(subject, today, ids)
        framing = WorkQueue.framing(@tenant, subject)
        catch_all = framing.find(&:catch_all)
        entries = framing.reject(&:catch_all).select { |queue| queue.segment&.active? }.map { |queue| [ queue.id, queue.segment.expression_object ] }
        query = Segments::Compiler.new(@tenant, today: today).classify_subjects(subject, entries, default_id: catch_all.id, only_ids: ids)
        t = @tenant.id.to_i
        connection = ActiveRecord::Base.connection
        Portfolio::Sql.execute("drop table if exists queue_calc")
        Portfolio::Sql.execute("create temporary table queue_calc (subject_id bigint primary key, item_id bigint) on commit drop")
        connection.exec_query("insert into queue_calc select subject_id, item_id from (#{query.sql}) q", "Queues", query.binds)
        quoted = connection.quote(subject)
        changed = Portfolio::Sql.run(<<~SQL)
          insert into queue_placements (tenant_id, subject, subject_id, work_queue_id, rank, created_at, updated_at)
          select #{t}, #{quoted}, c.subject_id, case when w.delivers then w.id end,
                 coalesce(mx.top, 0) + row_number() over (partition by w.id order by c.subject_id), now(), now()
            from queue_calc c join work_queues w on w.id = c.item_id
            left join (select work_queue_id, max(rank) as top from queue_placements where tenant_id = #{t} and work_queue_id is not null group by 1) mx on mx.work_queue_id = w.id
          on conflict (subject, subject_id) do update set work_queue_id = excluded.work_queue_id, rank = excluded.rank, updated_at = now()
           where queue_placements.work_queue_id is distinct from excluded.work_queue_id
        SQL
        unless ids
          Portfolio::Sql.execute("delete from queue_placements p where p.tenant_id = #{t} and p.subject = #{quoted} and not exists (select 1 from queue_calc c where c.subject_id = p.subject_id)")
          rank(subject, framing.select { |queue| queue.delivers && queue.active }, today)
        end
        Portfolio::Sql.execute("drop table queue_calc")
        changed
      end

      # A posição em cada fila pelo critério, o desempate e o sujeito mais antigo no CRM (R355), sobre os dados de apoio do dia.
      def rank(subject, queues, today)
        return if queues.empty?

        Portfolio::Sql.execute("drop table if exists queue_sort")
        Portfolio::Sql.execute("create temporary table queue_sort on commit drop as #{SortData.sql(subject, @tenant.id.to_i, ActiveRecord::Base.connection.quote(today))}")
        Portfolio::Sql.execute("create unique index on queue_sort (id)")
        queues.each do |queue|
          order = [ ORDER_SQL.fetch(queue.order_by), queue.order_tiebreak && ORDER_SQL.fetch(queue.order_tiebreak), "p.subject_id" ].compact.join(", ")
          Portfolio::Sql.execute(<<~SQL)
            update queue_placements q set rank = o.r from (
              select p.id, row_number() over (order by #{order}) as r
                from queue_placements p left join queue_sort d on d.id = p.subject_id where p.work_queue_id = #{queue.id.to_i}
            ) o where q.id = o.id and q.rank is distinct from o.r
          SQL
        end
        Portfolio::Sql.execute("drop table queue_sort")
      end
  end
end
