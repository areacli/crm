module Payments
  # Uma passada da lista de pagos de uma integração (12, revisão 4, R284b a R284d): o segundo caminho do pagamento, ao lado do webhook. Pede ao adaptador
  # os pagos desde a última passada que deu certo (com uma hora de sobra, no máximo 59 dias, o limite que o Bradesco aceita), grava cada aviso cujo
  # instrumento é desta integração e ainda espera o fato, e enfileira o processamento de sempre (`ProcessPaymentEventJob`: consulta antes de mudar, R283).
  # O mesmo pagamento já avisado pelo webhook tem o mesmo identificador e não vira outro aviso (R282); o aviso que terminou "ignorado" é reaberto (R284d).
  # A última passada só avança quando a lista inteira veio: a falha deixa o período para a próxima. Sem polling de tela: quem roda é a fila.
  class PaidList
    OVERLAP = 1.hour
    MAX_WINDOW = 59.days
    FIRST_WINDOW = 1.day

    Result = Data.define(:listed, :queued)

    # A integração está no horário da passada? `schedule`: `{ every: minutos }` ou `{ daily_at: "HH:MM" }` (hora de Brasília), do manifesto.
    def self.due?(account, schedule, now = Time.current)
      last = account.paid_listed_until
      if schedule[:every]
        last.nil? || last <= now - schedule[:every].to_i.minutes + 1.minute
      elsif schedule[:daily_at]
        hour, minute = schedule[:daily_at].to_s.split(":").map(&:to_i)
        today_at = now.in_time_zone("America/Sao_Paulo").change(hour: hour, min: minute)
        now >= today_at && (last.nil? || last < today_at)
      else
        false
      end
    end

    def initialize(account) = @account = account

    # Devolve o `Result`, ou nil quando não chamou o fornecedor (sem fornecedor no código ou na janela fora do ar, R284h).
    def call(now: Time.current)
      return unless @account.provider_available?

      adapter = @account.adapter
      return if adapter.quiet?(@account.modality, now)

      from = [ (@account.paid_listed_until || now - FIRST_WINDOW) - OVERLAP, now - MAX_WINDOW ].max
      notifications = adapter.list_paid(@account, from: from, to: now)
      queued = notifications.count { |notification| record(notification) }
      @account.update_columns(paid_listed_until: now)
      Result.new(listed: notifications.size, queued: queued)
    end

    private
      # Só o que pode mudar algo: pagamento de instrumento desta integração ainda não pago, ou devolução de instrumento pago. O resto (Pix de outro
      # sistema na mesma chave, pagamento que o webhook já trouxe) não grava nada.
      def record(notification)
        return false unless notification.kind.in?(%i[paid refunded]) && notification.external_id

        instrument = PaymentInstrument.find_by(account_id: @account.id, external_id: notification.external_id) or return false
        return false if notification.kind == :paid && instrument.state_paid?
        return false if notification.kind == :refunded && !instrument.state_paid?

        event, queue = PaymentEvent.record(@account, notification, reopen_ignored: notification.kind == :paid)
        ProcessPaymentEventJob.perform_later(event) if queue
        queue
      end
  end
end
