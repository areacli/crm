module Queues
  # Depois de um acionamento (15, R354, R356): os sujeitos da pessoa contatada (ela na fila de clientes e os contratos dela na de contratos)
  # ficam fora da entrega pelo intervalo do tipo do resultado, ou até a hora do retorno; no critério "mais tempo sem acionamento", vão para o
  # fim da fila; a entrega aberta de quem registrou se encerra; e o enquadramento desses sujeitos é refeito em segundo plano.
  module AfterContact
    module_function

    def call(attempt)
      contract_ids = ContractCustomer.where(customer_id: attempt.customer_id).pluck(:contract_id)
      Operations::Context.system do
        placements = QueuePlacement.where(subject: "customers", subject_id: attempt.customer_id)
                                   .or(QueuePlacement.where(subject: "contracts", subject_id: contract_ids)).includes(:work_queue)
        placements.each do |placement|
          queue = placement.work_queue or next
          available = attempt.return_at || attempt.contacted_at + queue.interval_after(attempt.result_kind)
          changes = { available_at: available }
          changes[:rank] = QueuePlacement.where(work_queue_id: queue.id).maximum(:rank).to_i + 1 if queue.order_by == "without_contact"
          placement.update!(changes)
        end
        QueueDelivery.open.where(user_id: attempt.user_id)
                     .where("(subject = 'customers' AND subject_id = ?) OR (subject = 'contracts' AND subject_id = ANY(ARRAY[?]::bigint[]))", attempt.customer_id, contract_ids.presence || [ 0 ])
                     .find_each { |delivery| delivery.finish!("recorded") }
      end
      QueuesSubjectJob.perform_later(attempt.tenant, { "customers" => [ attempt.customer_id ], "contracts" => contract_ids })
    end
  end
end
