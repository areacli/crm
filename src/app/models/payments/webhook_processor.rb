module Payments
  # Baixa o pagamento de um evento de webhook genérico (camada 6) já autenticado e guardado. Passa pelo mesmo caminho do arquivo e dos instrumentos
  # de pagamento (`ExternalPayment`): validação, unicidade por canal + identificador, pendente quando o título não está na carteira, políticas do
  # credor. O resultado fica numa importação de pagamentos já confirmada (origem "webhook"), para o registro de quem, quando e o que mudou.
  class WebhookProcessor
    def run(event)
      return unless event.received?

      channel = event.channel
      parsed = Gateway.for(channel.webhook_adapter).event(event.payload)
      return finish(event, :ignored, "evento #{parsed.kind.presence || 'sem tipo'} não é de pagamento recebido") unless parsed.payment

      result = ExternalPayment.new.pay(channel, parsed.payment, label: "webhook #{event.event_id}")
      finish(event, result.status, result.outcome)
    end

    private
      def finish(event, status, outcome)
        event.update!(status: status, outcome: outcome, processed_at: Time.current)
      end
  end
end
