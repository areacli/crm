module Payments
  # Atualiza um instrumento com o que o fornecedor diz AGORA (12, parte D, R283 e R284). É o único lugar que muda um instrumento para pago, vencido,
  # cancelado ou devolvido a partir de aviso ou conciliação, e ele sempre CONSULTA o fornecedor antes: o aviso só diz que vale a pena olhar, nunca
  # decide (corpo que diz "pago" com consulta que diz "ativo" não muda nada). Idempotente: repetir com o mesmo estado consultado não faz nada.
  #
  #   ativo, vencido ou falho (com identificador) -> pago: registra o pagamento no canal da conta pelo mesmo caminho do arquivo (ExternalPayment: baixa
  #   pelas políticas do credor, encargos por componente, promessas PRM- e acordos ACD- pelo número do objeto cobrado) e liga o instrumento a ele;
  #   ativo -> vencido ou cancelado; pago com devolução maior que a registrada -> estorno do pagamento ligado.
  #
  # `review`: o fato foi aceito (o instrumento está pago), mas o efeito no CRM espera alguém (sem título ligado, título fora da carteira, canal desativado).
  class InstrumentSync
    Outcome = Data.define(:kind, :text) # kind: applied, ignored ou review

    PAYABLE_STATES = %w[active expired failed].freeze
    # O meio entra com o nome que a planilha usa (o validador lê "cartão de crédito" e grava credit_card).
    METHODS = { "boleto" => "boleto", "pix" => "pix", "card" => "cartão de crédito" }.freeze
    # O valor que o aviso traz só vale como pista se for plausível (entre 1 centavo e 10 vezes o instrumento): o que o fornecedor consultado diz vem antes.
    HINT_FACTOR = 10

    def call(instrument, notification = nil)
      adopt_external_id(instrument, notification)
      return Outcome.new(:ignored, "instrumento ainda não emitido no fornecedor") if instrument.external_id.blank?
      return Outcome.new(:ignored, "fornecedor indisponível") unless instrument.account.provider_available?

      issued = consult(instrument)
      instrument.update_columns(reconciled_at: Time.current)
      outcomes = apply(instrument, issued, notification)
      Checkouts.sync(instrument.checkout) if instrument.checkout && outcomes.any?
      summarize(outcomes)
    end

    private
      # Cartão "não confirmado" (o tempo esgotou ao ler a resposta) ficou sem identificador do fornecedor: o aviso traz o nosso `custom_id`, e a consulta
      # logo adiante confirma se a cobrança existe e está paga. Só vale para o instrumento falho e ainda sem identificador, e para aviso já autenticado.
      def adopt_external_id(instrument, notification)
        return unless instrument.external_id.blank? && instrument.state_failed? && notification&.external_id.present?

        instrument.update!(external_id: notification.external_id)
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def consult(instrument)
        adapter = instrument.account.adapter
        case instrument.kind
        when "boleto" then adapter.fetch_boleto(instrument.account, instrument.external_id)
        when "pix" then adapter.fetch_pix(instrument.account, instrument.external_id)
        else adapter.fetch_card(instrument.account, instrument.external_id)
        end
      end

      def apply(instrument, issued, notification)
        outcomes = []
        instrument.with_lock do
          if issued.status == "paid" && instrument.state.in?(PAYABLE_STATES)
            outcomes << settle(instrument, issued, notification)
          elsif issued.status.in?(%w[canceled expired]) && instrument.state_active?
            instrument.update!(state: issued.status)
            outcomes << Outcome.new(:applied, issued.status == "canceled" ? "instrumento cancelado no fornecedor" : "instrumento vencido")
          end
          outcomes << refund(instrument, issued, notification) if instrument.state_paid? && issued.refunded_cents.to_i > instrument.refunded_cents
        end
        outcomes.compact
      end

      def settle(instrument, issued, notification)
        paid_cents = issued.paid_cents || hint(notification, instrument) || instrument.amount_cents
        paid_at = notification&.occurred_at || Time.current
        instrument.update!(state: "paid", paid_at: paid_at, paid_cents: paid_cents, failure_reason: nil)
        posting = post_payment(instrument, paid_cents, paid_at, notification)
        posting.kind == :review ? posting : Outcome.new(:applied, "instrumento pago: #{posting.text}")
      end

      # Entra no mesmo caminho do pagamento existente (R284): o pagamento é do canal da conta e identifica o título (ou a promessa, ou o acordo) pelo número.
      def post_payment(instrument, paid_cents, paid_at, notification)
        number = reference_number(instrument)
        return Outcome.new(:review, "instrumento pago sem título, promessa ou acordo ligado: a baixa espera o gestor") if number.blank?

        identifier = notification&.end_to_end_id.presence || "#{instrument.provider}:#{instrument.external_id}"
        paid_on = [ paid_at.in_time_zone.to_date, Date.current ].min
        result = ExternalPayment.new.pay(instrument.account.channel, { identifier: identifier, document: instrument.payer_document, bill_number: number, paid_on: paid_on,
                                                                       amount_cents: paid_cents, payment_method: METHODS.fetch(instrument.kind) },
                                         label: "instrumento #{instrument.custom_id}")
        return Outcome.new(:review, "o pagamento não entrou: #{result.outcome}") if result.status == :rejected

        payment = Payment.find_by(tenant_id: instrument.tenant_id, channel_id: instrument.account.channel_id, identifier: identifier)
        instrument.update!(payment: payment)
        Outcome.new(:applied, result.outcome)
      end

      # Devolução de Pix ou reembolso de cartão entram como estorno do pagamento ligado (R284).
      def refund(instrument, issued, notification)
        payment = instrument.payment
        return Outcome.new(:review, "devolução de instrumento sem pagamento registrado") unless payment

        delta = [ issued.refunded_cents - instrument.refunded_cents, payment.reversible_cents ].min
        if delta.positive?
          result = ExternalPayment.new.reverse(instrument.account.channel, payment_identifier: payment.identifier, identifier: "#{instrument.custom_id}:#{issued.refunded_cents}",
                                               reversed_on: [ (notification&.occurred_at || Time.current).in_time_zone.to_date, Date.current ].min, amount_cents: delta,
                                               reason: I18n.t("payments.sync.refund_reason.#{instrument.kind}"), label: "devolução #{instrument.custom_id}")
          return Outcome.new(:review, "o estorno não entrou: #{result.outcome}") if result.status == :rejected
        end
        instrument.update!(refunded_cents: issued.refunded_cents)
        Outcome.new(:applied, "devolução registrada como estorno")
      end

      def hint(notification, instrument)
        cents = notification&.amount_cents
        cents if cents.is_a?(Integer) && cents.between?(1, instrument.amount_cents * HINT_FACTOR)
      end

      # O número que identifica o objeto cobrado no pagamento: título (`bill`), promessa (`promise`, PRM-) ou acordo (`agreement`, ACD-).
      def reference_number(instrument)
        model = { "bill" => Bill, "promise" => PaymentPromise, "agreement" => Agreement }[instrument.reference_type] or return
        model.where(tenant_id: instrument.tenant_id).find_by(id: instrument.reference_id)&.number
      end

      # Se alguma parte pede o gestor, o aviso fica em `review`; senão, `applied` quando algo mudou, e `ignored` quando o consultado era igual ao que já havia.
      def summarize(outcomes)
        return Outcome.new(:ignored, "o estado consultado não mudou nada") if outcomes.empty?

        review = outcomes.find { |outcome| outcome.kind == :review }
        review || Outcome.new(:applied, outcomes.map(&:text).join("; "))
      end
  end
end
