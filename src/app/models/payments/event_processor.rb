module Payments
  # Processa um aviso guardado (12, parte D, R283 e R284), no job da fila `webhooks`. O adaptador completa o aviso (a Efí troca o token pela lista de
  # mudanças), acha-se o instrumento da MESMA conta (nunca de outra: V10) e `InstrumentSync` consulta o fornecedor antes de mudar qualquer coisa.
  # Idempotente: só trabalha com aviso `received`.
  class EventProcessor
    def run(event)
      return unless event.state_received?

      event.increment!(:attempts)
      account = event.account
      return event.finish!(:ignored, I18n.t("payments.events.provider_unavailable")) unless account.provider_available?

      notifications = account.adapter.expand_notification(account, event.to_notification)
      return event.finish!(:ignored, I18n.t("payments.events.nothing_to_do")) if notifications.empty?

      found = notifications.filter_map { |notification| (instrument = instrument_of(account, notification)) && [ instrument, notification ] }
      return event.finish!(:ignored, I18n.t("payments.events.not_ours")) if found.empty?

      outcomes = found.map { |instrument, notification| InstrumentSync.new.call(instrument, notification) }
      state = if outcomes.any? { |outcome| outcome.kind == :review } then :review
      elsif outcomes.any? { |outcome| outcome.kind == :applied } then :applied
      else :ignored
      end
      event.finish!(state, outcomes.map(&:text).uniq.join("; "), instrument: found.first.first)
    end

    private
      def instrument_of(account, notification)
        scope = PaymentInstrument.where(account_id: account.id)
        (scope.find_by(external_id: notification.external_id) if notification.external_id) || (scope.find_by(custom_id: notification.custom_id) if notification.custom_id)
      end
  end
end
