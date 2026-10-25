module Payments
  # Cobrança de cartão do checkout (12, R278): o servidor recebe só o `payment_token` e o número de parcelas, que a biblioteca do fornecedor gerou no
  # navegador; dado de cartão nunca chega aqui, nem ao banco, nem ao log. Cada tentativa é um instrumento do tipo `card`.
  #
  # Idempotência (clique duplo, retentativa): o nosso `custom_id` sai do link e do token (SHA-256), então o mesmo token no mesmo link é a mesma
  # tentativa e devolve o mesmo resultado sem cobrar de novo. Uma tentativa em curso (`emitting`) barra as outras. O fornecedor é chamado fora de
  # qualquer trava do banco; a tentativa é gravada antes da chamada. Falha de rede que pode ter cobrado (tempo esgotado ao ler a resposta) deixa o link
  # "não confirmado" e não permite nova tentativa: o credor confere no painel do fornecedor. Falha em que a conexão nem saiu libera repetir o mesmo token.
  class CardCharger
    # `kind`: approved, declined, processing, unconfirmed, unavailable, error, paid, not_payable, invalid. `code` e `retry` valem na recusa.
    Outcome = Data.define(:kind, :code, :retry) do
      def initialize(kind:, code: nil, retry: false) = super
    end

    TOKEN_FORMAT = /\A[A-Za-z0-9_\-.:=+\/]{8,512}\z/

    def charge(checkout, payment_token:, installments:)
      token = payment_token.to_s
      count = installments.to_s.match?(/\A\d{1,2}\z/) ? installments.to_i : 0
      return Outcome.new(kind: :invalid) unless token.match?(TOKEN_FORMAT) && count.positive?

      Checkouts.settle_stale(checkout)
      account = Checkouts.card_account(checkout.tenant, checkout.environment)
      instrument, early = reserve(checkout, account, token, count)
      return early if early

      call_provider(checkout, account, instrument, token, count)
    end

    private
      # Decide, com a linha do link travada, se esta chamada cobra, repete uma tentativa que nem saiu, ou só devolve o resultado que já existe.
      def reserve(checkout, account, token, count)
        instrument = early = nil
        checkout.with_lock do
          early = blocked(checkout, account, count)
          unless early
            custom_id = Digest::SHA256.hexdigest("#{checkout.id}:#{token}").first(32)
            instrument = checkout.instruments.find_by(custom_id: custom_id)
            if instrument
              early = existing_outcome(instrument)
              instrument = reopen(instrument) if early.nil?
            elsif checkout.instruments.any? { |i| i.card? && i.state_emitting? }
              early = Outcome.new(kind: :processing)
            else
              instrument = create_attempt(checkout, account, custom_id, count)
            end
          end
        end
        [ instrument, early ]
      end

      def blocked(checkout, account, count)
        case checkout.state
        when "paid" then Outcome.new(kind: :paid)
        when "card_approved" then Outcome.new(kind: :approved)
        when "card_unconfirmed" then Outcome.new(kind: :unconfirmed)
        else
          return Outcome.new(kind: :not_payable) unless checkout.card_payable? && checkout.available?
          return Outcome.new(kind: :unavailable) unless account&.provider_available?

          Outcome.new(kind: :invalid) unless count <= account.config.fetch("max_installments", 1).to_i
        end
      end

      def existing_outcome(instrument)
        summary = instrument.response_summary
        case instrument.state
        when "emitting" then Outcome.new(kind: :processing)
        when "active", "paid" then Outcome.new(kind: :approved)
        when "failed"
          return nil if summary["retryable"] # a conexão nem saiu: o mesmo token pode ser usado de novo
          return Outcome.new(kind: :unconfirmed) if summary["unconfirmed"]
          return Outcome.new(kind: :error) if summary["error"]

          Outcome.new(kind: :declined, code: summary["refusal_code"], retry: summary["retry"] == true)
        else Outcome.new(kind: :not_payable)
        end
      end

      def reopen(instrument)
        instrument.update!(state: "emitting", failure_reason: nil, response_summary: {}, attempts: instrument.attempts + 1)
        instrument
      end

      def create_attempt(checkout, account, custom_id, count)
        PaymentInstrument.create!(tenant: checkout.tenant, account: account, provider: account.provider, customer: checkout.customer, checkout: checkout, kind: "card", amount_cents: checkout.amount_cents,
                                  due_on: Date.current, custom_id: custom_id, reference_type: checkout.reference_type, reference_id: checkout.reference_id, payer_name: checkout.payer_name,
                                  payer_document: checkout.payer_document, payer_address: checkout.payer_address, attempts: 1, response_summary: { "installments" => count })
      end

      def call_provider(checkout, account, instrument, token, count)
        payer = { name: checkout.payer_name, document: checkout.payer_document, address: checkout.payer_address, email: checkout.payer_email, phone: checkout.payer_phone }
        result = account.adapter.charge_card(account, custom_id: instrument.custom_id, amount_cents: checkout.amount_cents, installments: count, payment_token: token, payer: payer,
                                                      description: checkout.description, notification_url: WebhookUrl.for(account))
        settle(checkout, instrument, result, count)
      rescue Providers::NetworkError => error
        # Seguro repetir só quando o pedido nem chegou ao fornecedor; no resto, pode ter cobrado.
        if error.retry_safe
          instrument.update!(state: "failed", failure_reason: error.message.to_s.first(300), response_summary: { "retryable" => true, "installments" => count })
          Outcome.new(kind: :unavailable)
        else
          unconfirmed(checkout, instrument, error.message)
        end
      rescue Providers::Error => error
        instrument.update!(state: "failed", failure_reason: error.message.to_s.first(300), response_summary: { "error" => true, "installments" => count })
        Outcome.new(kind: :error)
      end

      def settle(checkout, instrument, result, count)
        if result.declined?
          instrument.update!(state: "failed", external_id: result.external_id.presence, failure_reason: result.refusal_reason.to_s.first(300).presence,
                             response_summary: { "refusal_code" => result.refusal_code, "retry" => result.retry, "installments" => count })
          Outcome.new(kind: :declined, code: result.refusal_code, retry: result.retry)
        elsif result.external_id.blank?
          unconfirmed(checkout, instrument, I18n.t("payments.instruments.no_identifier"))
        else
          instrument.update!(state: result.status == "paid" ? "paid" : "active", external_id: result.external_id, issued_at: Time.current,
                             response_summary: { "installments" => result.installments, "total_cents" => result.amount_cents }.compact)
          Checkouts.sync(checkout)
          Outcome.new(kind: :approved)
        end
      end

      def unconfirmed(checkout, instrument, detail)
        instrument.update!(state: "failed", failure_reason: detail.to_s.first(300), response_summary: { "unconfirmed" => true })
        checkout.update!(state: "card_unconfirmed")
        Checkouts.broadcast(checkout)
        Outcome.new(kind: :unconfirmed)
      end
  end
end
