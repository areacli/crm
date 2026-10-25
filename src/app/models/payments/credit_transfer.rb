module Payments
  # Transferência de crédito entre contratos do mesmo credor (03, R55a): o único caminho para o crédito mudar de contrato. A permissão 17
  # já foi conferida pela política no credor do contrato de origem. Um lançamento negativo na origem e um positivo no destino; nada é
  # apagado e o total do credor não muda. Não é pagamento: não conta como recuperado (R58).
  class CreditTransfer
    def initialize(actor) = @actor = actor

    def transfer(from:, to:, cents:, reason:)
      raise Access::Refused, I18n.t("payments.credit_transfer.other_tenant") if from.tenant_id != to.tenant_id
      raise Access::Refused, I18n.t("payments.credit_transfer.same_contract") if from.id == to.id
      raise Access::Refused, I18n.t("payments.credit_transfer.reason_required") if reason.to_s.strip.empty?
      raise Access::Refused, I18n.t("payments.credit_transfer.invalid_amount") unless cents.to_i.positive?

      ApplicationRecord.transaction do
        # Trava o contrato de origem: duas transferências ao mesmo tempo não gastam o mesmo crédito.
        from.lock!
        # R55a, R239: o disponível e o aguardando alocação se transferem; o bloqueado, não; o aguardando alocação, não durante a marca "em reversão"; o que cobre atraso de
        # acordo ativo, não enquanto cobrir (R232b).
        marked = Agreements::Reversion.marked?(from)
        available = from.credit_cents - Agreements::CreditShield.protected_cents(from) + (marked ? 0 : Agreements::CreditBook.balance(from.id, "awaiting"))
        raise Access::Refused, I18n.t("payments.credit_transfer.above_available", available: Money.format(available)) if cents > available

        now = Time.current
        note = reason.to_s.strip[0, 300]
        from_available = [ cents, from.credit_cents - Agreements::CreditShield.protected_cents(from) ].min
        from_awaiting = cents - from_available
        Agreements::CreditBook.move!(from.id, from: "awaiting", to: "available", cents: from_awaiting, reason: "transfer", user: @actor, note: note, at: now) if from_awaiting.positive?
        Credit.create!(tenant_id: from.tenant_id, contract: from, user: @actor, kind: :transfer_out, amount_cents: -cents, reason: :transfer, note: note,
                       related_contract: to, occurred_at: now)
        Credit.create!(tenant_id: to.tenant_id, contract: to, user: @actor, kind: :transfer_in, amount_cents: cents, reason: :transfer, note: note,
                       related_contract: from, occurred_at: now)
        [ [ from, -cents ], [ to, cents ] ].each do |contract, amount|
          Change.create!(tenant_id: contract.tenant_id, user: @actor, subject_type: "contract", subject_id: contract.id, event: "credit_transferred",
                         field: "credit", after: amount.to_s)
        end
      end
    end
  end
end
