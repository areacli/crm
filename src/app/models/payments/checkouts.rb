module Payments
  # Links de checkout (12, parte C, R277 a R280). Só por serviço: o back office não tem tela para criar link (instrução do Paulo). O link junta o que o
  # cliente pode usar para pagar o mesmo valor: o cartão (checkout transparente, se o credor tem conta de cartão ativa) e os instrumentos já emitidos
  # (boleto e Pix, que a página serve daqui). O valor é o emitido (R280): recalcular é emitir outro instrumento e outro link.
  module Checkouts
    class Refused < StandardError; end

    # R277: o link vale até o vencimento do instrumento mais 30 dias (ou 30 dias a partir de hoje, quando só há cartão); o gestor renova.
    VALID_AFTER_DUE = 30.days
    # Tentativa de cartão que ficou "em curso" por mais que isto (processo que caiu depois de gravar a tentativa): não se sabe se cobrou.
    STALE_ATTEMPT = 5.minutes

    module_function

    # `instruments`: boletos e Pix ativos (do mesmo credor e do mesmo valor). `card`: nil = oferece se houver conta de cartão ativa; true exige; false não oferece.
    # `amount_cents` só é obrigatório sem instrumentos. `highlight`: a forma em destaque (padrão: a primeira oferecida, na ordem Pix, boleto, cartão).
    def create(tenant:, customer:, instruments: [], card: nil, amount_cents: nil, description: nil, highlight: nil, environment: "production", expires_at: nil, reference: nil)
      instruments = Array(instruments)
      amount_cents = checkout_amount(tenant, instruments, amount_cents)
      payer = Payer.snapshot_with_contacts(customer)
      modalities = instruments.map(&:kind).uniq
      modalities << "card" if offer_card?(tenant, environment, card, payer)
      raise Refused, I18n.t("payments.checkout.errors.nothing_to_offer") if modalities.empty?

      highlight = highlight.to_s.presence || (%w[pix boleto card] & modalities).first
      expires_at ||= (instruments.map(&:due_on).max&.end_of_day || Time.current) + VALID_AFTER_DUE
      checkout = PaymentCheckout.new(tenant: tenant, customer: customer, amount_cents: amount_cents, description: description.to_s.first(200).presence, environment: environment.to_s,
                                     modalities: modalities, highlight: highlight, expires_at: expires_at, reference_type: reference&.first&.to_s, reference_id: reference&.last, **payer)
      PaymentCheckout.transaction do
        checkout.save!
        instruments.each { |instrument| instrument.update!(checkout: checkout) }
      end
      checkout
    rescue ActiveRecord::RecordInvalid => error
      raise Refused, error.record.errors.full_messages.to_sentence
    end

    # R277: o gestor renova um link ainda não pago nem cancelado (a partir de hoje ou do vencimento atual, o que for mais tarde).
    def renew(checkout, days: 30)
      raise Refused, I18n.t("payments.checkout.errors.not_renewable") if checkout.state_paid? || checkout.state_canceled?

      checkout.update!(expires_at: [ checkout.expires_at, Time.current ].max + days.days)
      checkout
    end

    def cancel(checkout)
      raise Refused, I18n.t("payments.checkout.errors.paid_untouchable") if checkout.state_paid?

      checkout.update!(state: "canceled")
      broadcast(checkout)
      checkout
    end

    # Recalcula o estado do link a partir dos instrumentos dele (chamado quando um instrumento muda de estado: o cartão aprovado aqui; o pagamento
    # confirmado, na parte D). Pago ganha de tudo; cartão aprovado ganha de aberto; cancelado e "não confirmado" só saem para pago.
    def sync(checkout)
      checkout.instruments.reload
      new_state =
        if checkout.instruments.any?(&:state_paid?) then "paid"
        elsif checkout.state_paid? || checkout.state_canceled? then checkout.state
        elsif checkout.instruments.any? { |i| i.card? && i.state_active? } then "card_approved"
        elsif checkout.state_card_unconfirmed? then "card_unconfirmed"
        else "open"
        end
      return checkout if new_state == checkout.state

      checkout.update!(state: new_state)
      broadcast(checkout)
      checkout
    end

    # Tentativa de cartão que ficou em curso tempo demais: não se sabe se cobrou. O link passa a "não confirmado" (não se tenta de novo; o credor confere).
    def settle_stale(checkout, now: Time.current)
      stale = checkout.instruments.select { |i| i.card? && i.state_emitting? && i.updated_at < now - STALE_ATTEMPT }
      return checkout if stale.empty?

      stale.each { |attempt| attempt.update!(state: "failed", failure_reason: I18n.t("payments.checkout.errors.stale_attempt")) }
      checkout.update!(state: "card_unconfirmed") if checkout.state_open?
      broadcast(checkout)
      checkout
    end

    # Avisa a página aberta (sem login, canal por token) de que o estado mudou; a página busca o trecho de novo.
    def broadcast(checkout)
      PaymentCheckoutChannel.broadcast_to(checkout, { event: "checkout-changed" })
    end

    def card_account(tenant, environment)
      tenant.payment_accounts.active.find_by(modality: "card", environment: environment.to_s)
    end

    def checkout_amount(tenant, instruments, amount_cents)
      instruments.each do |instrument|
        raise Refused, I18n.t("payments.checkout.errors.other_tenant") unless instrument.tenant_id == tenant.id
        raise Refused, I18n.t("payments.checkout.errors.instrument_not_active") unless instrument.state_active? && !instrument.card?
      end
      amounts = instruments.map(&:amount_cents).uniq
      raise Refused, I18n.t("payments.checkout.errors.amounts_differ") if amounts.size > 1

      amount = amounts.first || amount_cents
      raise Refused, I18n.t("payments.checkout.errors.amount_required") if amount.blank?
      raise Refused, I18n.t("payments.checkout.errors.amount_differs") if amount_cents && amounts.first && amount_cents != amounts.first

      amount.to_i
    end

    # O cartão só é oferecido com conta de cartão ativa (de fornecedor instalado) e com documento válido do pagador (a Efí o exige).
    def offer_card?(tenant, environment, card, payer)
      return false if card == false

      account = card_account(tenant, environment)
      available = account&.provider_available? && Document.problem(payer[:payer_document]).nil?
      raise Refused, I18n.t("payments.checkout.errors.card_unavailable") if card && !available

      available
    end
  end
end
