# Tarefa diária das contas de pagamento (12, R264): avisa os certificados a vencer. Agendada em config/schedule.yml.
class PaymentAccountsDailyJob < ApplicationJob
  queue_as :default

  def perform = Payments::CertificateWatch.new.call
end
