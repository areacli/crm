module Agreements
  # Efetivação do acordo (11, R225, N5): pelo pagamento da entrada ou pelo aceite (política congelada). Os títulos originais passam a renegociados (saem do vencido, das
  # faixas e do valor atualizado), e os títulos de acordo passam a ser cobrados como qualquer título em aberto, pelo saldo devedor. A entrada deixa de ser "a pagar" e
  # passa a ser título vigente. Idempotente: a confirmação de pagamentos já pode ter gravado parte dos estados.
  module Effectuation
    module_function

    # O acordo à vista segue "efetivação do acordo à vista" (P4): padrão, a geral; alternativa, só pelo pagamento.
    def by_acceptance?(agreement)
      general = agreement.frozen_policy("effectuation") == "acceptance"
      return general unless agreement.mode_cash?

      agreement.frozen_policy("cash_effectuation") == "payment_only" ? false : general
    end

    def call(agreement, by:, at: Time.current, actor: nil)
      return agreement unless agreement.state_awaiting_effectuation?

      ApplicationRecord.transaction do
        agreement.update!(state: "active_on_time", effectuated_at: at, effectuated_by: by)
        # A confirmação de pagamentos pode já ter gravado os originais como renegociados: o acordo anterior é achado pelos originais, em qualquer situação.
        previous_ids = Bill.where(id: agreement.agreement_bills.select(:bill_id)).where.not(agreement_id: nil).distinct.pluck(:agreement_id)
        Bill.where(id: agreement.agreement_bills.select(:bill_id), status: "active").update_all(status: "renegotiated", updated_at: Time.current)
        Bill.where(agreement_id: agreement.id, status: "scheduled").update_all(status: "active", updated_at: Time.current)
        AgreementEvent.log!(agreement, "effectuated", user: actor, data: { "by" => by })
        Change.record!(tenant_id: agreement.tenant_id, user: actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state",
                       before: "awaiting_effectuation", after: "active_on_time", note: by)
        # R250: o acordo anterior fica renegociado na efetivação do novo, se não sobra título próprio em aberto.
        previous_ids.each { |id| Renegotiation.after_effectuation(Agreement.find(id), agreement) }
      end
      agreement
    end
  end
end
