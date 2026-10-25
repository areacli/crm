module Payments
  # Reprocessagem segura dos avisos de um credor (12, parte D): os que falharam e os que ficaram "recebidos" tempo demais (a fila perdeu o job). O
  # processamento consulta o fornecedor e é idempotente, então repetir não duplica pagamento nem estorno. Cada aviso volta no máximo `MAX_RESTARTS`
  # vezes; depois fica `failed` à espera de alguém (o resultado e o motivo estão no próprio aviso). Consulta: `index_payment_events_pending`.
  class EventReprocessor
    STUCK_AFTER = 15.minutes

    def initialize(tenant) = @tenant = tenant

    def call(now: Time.current)
      restarted = 0
      PaymentEvent.where(tenant_id: @tenant.id).pending.where("state = 'failed' or created_at <= ?", now - STUCK_AFTER).find_each do |event|
        restarts = event.summary.fetch("restarts", 0)
        next if restarts >= PaymentEvent::MAX_RESTARTS

        event.update!(state: "received", attempts: 0, outcome: nil, processed_at: nil, summary: event.summary.merge("restarts" => restarts + 1))
        ProcessPaymentEventJob.perform_later(event)
        restarted += 1
      end
      restarted
    end
  end
end
