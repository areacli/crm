# Despacha as passadas da lista de pagos (12, revisão 4, R284c), a cada 10 minutos (config/schedule.yml): uma por integração ativa cujo manifesto
# declara a lista para a modalidade e que está no horário dela (Pix a cada 10 minutos; boleto do Bradesco uma vez por dia, às 7h20). Roda com ou sem
# webhook: nenhuma configuração "o webhook está ligado" muda isto.
class PaymentPaidListsDispatchJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    PaymentAccount.active.find_each do |account|
      next unless account.provider_available?

      schedule = account.adapter.paid_list_schedule(account.modality) or next
      PaymentPaidListJob.perform_later(account) if Payments::PaidList.due?(account, schedule, now)
    end
  end
end
