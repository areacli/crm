# Medição das filas (plano técnico da camada 19, V4): 200 mil contratos numa fila, o recálculo completo e o de um sujeito, e N operadores
# pedindo "Próximo" ao mesmo tempo por alguns segundos, com um acionamento a cada entrega. Mede o tempo do "Próximo" e confere que nenhum
# contrato foi entregue a dois operadores ao mesmo tempo. Só fora de produção, num banco descartável.
require_relative "../measure_data"

namespace :crm do
  desc "Mede as filas: crm:measure_queues[contratos,operadores,segundos]"
  task :measure_queues, %i[contracts operators seconds] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info
    count = (args[:contracts].presence || 200_000).to_i
    operators = (args[:operators].presence || 50).to_i
    seconds = (args[:seconds].presence || 120).to_i
    ActiveRecord::Base.establish_connection(ActiveRecord::Base.connection_db_config.configuration_hash.except(:pool).merge(max_connections: operators + 5))
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      puts format("%-76s %8.3f s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      result
    end

    tenant = Tenant.provision!("Medição das filas #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    Operations::Context.system do
      measure.call("massa: #{count} contratos, #{count * 3} títulos") do
        MeasureData.portfolio(t, count, bills_per: 3, bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - ((i * 37 + n * 11) % 500) + 60,
                                                                           amount_cents: 5000 + (i * 7919 + n * 131) % 250_000 } })
      end
      MeasureData.analyze(%w[customers contracts contract_customers bills])
      segment = Segment.create!(tenant: tenant, name: "Em atraso", subject: "contracts", expression: { "all" => [ { "path" => "in_arrears", "op" => "is" } ] })
      queue = WorkQueue.create!(tenant: tenant, subject: "contracts", name: "Fila da medição", segment: segment, position: 1, order_by: "overdue_balance",
                                order_tiebreak: "without_contact")
      group = QueueGroup.create!(tenant: tenant, name: "Medição")
      QueueGroupQueue.create!(queue_group: group, work_queue: queue, position: 1)
      profile = tenant.profiles.find_by!(name: "Operador")
      users = (1..operators).map do |index|
        User.create!(name: "Operador #{index}", email_address: "medicao-filas-#{t}-#{index}@exemplo.com.br", password: "lua-cheia-sobre-o-rio-82").tap do |user|
          Membership.create!(user: user, tenant: tenant, profile: profile)
          QueueGroupUser.create!(queue_group: group, user: user)
        end
      end
      measure.call("recálculo completo das filas (#{count} contratos)") { Queues::Recalculation.new(tenant).apply }
      puts "  na fila: #{QueuePlacement.where(work_queue: queue).count}"
      some = QueuePlacement.where(work_queue: queue).limit(1).pluck(:subject_id)
      measure.call("recálculo de um sujeito") { Queues::Recalculation.new(tenant).apply(only: { "contracts" => some }) }

      result = ContactResult.where(tenant_id: t).first
      times = Concurrent::Array.new
      deliveries = Concurrent::AtomicFixnum.new
      stop_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      threads = users.map do |user|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Operations::Context.for_user(user) do
              while Process.clock_gettime(Process::CLOCK_MONOTONIC) < stop_at
                started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                delivery = Queues::NextDelivery.new(user).call.delivery
                times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
                break unless delivery

                deliveries.increment
                customer_id = ContractCustomer.where(contract_id: delivery.subject_id).pick(:customer_id)
                ContactAttempt.create!(tenant_id: t, customer_id: customer_id, contract_id: delivery.subject_id, user: user, result: result, result_kind: result.kind,
                                       channel: "phone", contacted_at: Time.current)
              end
            end
          end
        end
      end
      threads.each(&:join)
      sorted = times.sort
      pick = ->(fraction) { sorted[(sorted.size * fraction).floor.clamp(0, sorted.size - 1)] }
      puts format("%-76s %8d", "entregas em #{seconds} s com #{operators} operadores", deliveries.value)
      puts format("%-76s %8.3f s", "Próximo: mediana", pick.call(0.5))
      puts format("%-76s %8.3f s", "Próximo: 95%", pick.call(0.95))
      puts format("%-76s %8.3f s", "Próximo: pior", sorted.last)
      overlaps = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
        select count(*) from queue_deliveries a join queue_deliveries b on a.subject_id = b.subject_id and a.id < b.id
         where a.tenant_id = #{t} and a.delivered_at < coalesce(b.ended_at, now()) and b.delivered_at < coalesce(a.ended_at, now())
      SQL
      puts format("%-76s %8d", "entregas do mesmo contrato a dois operadores ao mesmo tempo", overlaps)
    end
  end
end

namespace :crm do
  desc "Mede o Próximo em vários processos sobre a última massa da medição: crm:measure_queues_next[processos,operadores_por_processo,segundos,pausa]"
  task :measure_queues_next, %i[processes threads seconds pause] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    processes = (args[:processes].presence || 5).to_i
    threads = (args[:threads].presence || 10).to_i
    seconds = (args[:seconds].presence || 60).to_i
    # Pausa entre um acionamento e o próximo pedido (o tempo da ligação); 0 = sem pausa (carga máxima). Todos começam no mesmo instante.
    pause = (args[:pause].presence || 0).to_f
    start_at = Time.current.to_f + 5
    tenant = Tenant.where("name like 'Medição das filas%'").order(:id).last or abort "Rode antes crm:measure_queues."
    users = User.where("email_address like ?", "medicao-filas-#{tenant.id}-%").order(:id).first(processes * threads)
    result = ContactResult.where(tenant_id: tenant.id).first
    QueuePlacement.where(tenant: tenant).update_all(available_at: nil)
    QueueDelivery.open.where(tenant: tenant).update_all(ended_at: Time.current, end_reason: "released")
    config = ActiveRecord::Base.connection_db_config.configuration_hash.except(:pool).merge(max_connections: threads + 2)
    files = (0...processes).map { |index| Rails.root.join("tmp/medicao-filas-#{index}.txt") }
    ActiveRecord::Base.connection_pool.disconnect!
    pids = files.each_with_index.map do |file, index|
      fork do
        ActiveRecord::Base.establish_connection(config)
        sleep [ start_at - Time.current.to_f, 0 ].max
        stop_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        times = Concurrent::Array.new
        users.slice(index * threads, threads).map do |user|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              Operations::Context.for_user(user) do
                while Process.clock_gettime(Process::CLOCK_MONOTONIC) < stop_at
                  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  delivery = Queues::NextDelivery.new(user).call.delivery
                  times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
                  break unless delivery

                  customer_id = ContractCustomer.where(contract_id: delivery.subject_id).pick(:customer_id)
                  ContactAttempt.create!(tenant_id: tenant.id, customer_id: customer_id, contract_id: delivery.subject_id, user: user, result: result,
                                         result_kind: result.kind, channel: "phone", contacted_at: Time.current)
                  sleep(pause * (0.75 + rand / 2)) if pause.positive?
                end
              end
            end
          end
        end.each(&:join)
        File.write(file, times.join("\n"))
      end
    end
    pids.each { |pid| Process.wait(pid) }
    ActiveRecord::Base.establish_connection(config)
    sorted = files.flat_map { |file| File.read(file).split.map(&:to_f) }.sort
    files.each { |file| FileUtils.rm_f(file) }
    pick = ->(fraction) { sorted[(sorted.size * fraction).floor.clamp(0, sorted.size - 1)] }
    puts format("%d processos × %d operadores, %d s, pausa %.0f s: %d pedidos; mediana %.3f s, 95%% %.3f s, pior %.3f s", processes, threads, seconds, pause, sorted.size,
                pick.call(0.5), pick.call(0.95), sorted.last)
    overlaps = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
      select count(*) from queue_deliveries a join queue_deliveries b on a.subject_id = b.subject_id and a.id < b.id
       where a.tenant_id = #{tenant.id} and a.delivered_at < coalesce(b.ended_at, now()) and b.delivered_at < coalesce(a.ended_at, now())
    SQL
    puts "entregas do mesmo contrato a dois operadores ao mesmo tempo: #{overlaps}"
  end
end
