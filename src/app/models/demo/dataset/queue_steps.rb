module Demo
  class Dataset
    # Filas (15) na Escola Alfa: o enquadramento de contratos com "Promessa ou acordo em dia" sem fila, o callback pelo retorno combinado, o
    # atraso recente e o antigo; o grupo da equipe com o operador e o gestor públicos, e o da Recupera com o usuário público de operação.
    module QueueSteps
      QUEUES = [
        [ "Promessa ou acordo em dia", [ { "any" => [ { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "in", "value" => %w[pending open] } },
                                                      { "path" => "agreements", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "active_on_time" } } ] } ],
          { delivers: false } ],
        [ "Callback", [ { "path" => "return_days", "op" => "lte", "value" => 0 } ], { order_by: "return_at", lock_minutes: 10 } ],
        [ "Atraso de 1 a 90 dias", [ { "path" => "overdue_days", "op" => "between", "value" => [ 1, 90 ] } ], { order_by: "overdue_balance", order_tiebreak: "without_contact" } ],
        [ "Atraso acima de 90 dias", [ { "path" => "overdue_days", "op" => "gt", "value" => 90 } ], { order_by: "overdue_days", order_tiebreak: "overdue_balance" } ]
      ].freeze

      private
        def queues(tenant)
          created = QUEUES.each_with_index.map do |(name, conditions, options), index|
            segment = Segment.create!(tenant: tenant, name: "Fila: #{name}", subject: "contracts", expression: { "all" => conditions })
            WorkQueue.create!(tenant: tenant, subject: "contracts", name: name, segment: segment, position: index + 1, **options)
          end
          delivering = created.select(&:delivers)
          team = QueueGroup.create!(tenant: tenant, name: "Equipe da escola")
          [ @operator, @manager ].each { |user| QueueGroupUser.create!(queue_group: team, user: user) }
          delivering.each_with_index { |queue, index| QueueGroupQueue.create!(queue_group: team, work_queue: queue, position: index + 1) }
          if @operation_user
            partner = QueueGroup.create!(tenant: tenant, name: "Recupera")
            QueueGroupUser.create!(queue_group: partner, user: @operation_user)
            delivering.each_with_index { |queue, index| QueueGroupQueue.create!(queue_group: partner, work_queue: queue, position: index + 1) }
          end
          tenant.setting.update!(queue_rules_version: tenant.setting.queue_rules_version + 1)
          Queues::Recalculation.new(tenant).apply(today: today)
        end
    end
  end
end
