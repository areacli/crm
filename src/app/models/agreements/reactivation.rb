module Agreements
  # Pagamento no prazo importado depois da quebra (11, R236a, política congelada "reativa o acordo", DA16): o acordo volta ao estado que teria com o pagamento, e o que a quebra
  # criou é desfeito, com o evento "reativado" no arquivo. A quebra deixa de contar para a marca "já quebrou acordo" (R248). Não reativa se, entre a quebra e o pagamento, os títulos
  # liberados receberam promessa, acordo ou pagamento de fora do acordo, nem se o crédito usado na entrada não pode ser consumido de novo (o pagamento então segue a R231).
  module Reactivation
    module_function

    def enabled?(agreement) = agreement.frozen_policy("reactivation") == "reactivates" && agreement.break_kind != "manual"

    # Quebra antes da efetivação: o pagamento da entrada até o fim da tolerância reativa o acordo aguardando efetivação.
    def before_effectuation?(agreement, pay_date)
      return false unless agreement.state_broken? && agreement.break_kind == "before_effectuation" && enabled?(agreement)

      entry = Bill.find_by(agreement_id: agreement.id, number: Titles.number_of(agreement, 0)) or return false
      return false unless pay_date <= agreement.deadline_for(entry, agreement.tolerance_days)
      return false if agreement.credit_down_cents.positive?

      originals = agreement.agreement_bills.includes(:bill)
      free = originals.all? { |item| item.bill.active? && item.bill.amount_cents == item.amount_cents && !AgreementBill.where(bill_id: item.bill_id, held: true).exists? && !PaymentPromiseBill.where(bill_id: item.bill_id, held: true).exists? }
      free && !CreditUse.unavailable(agreement)
    end

    def restore_before_effectuation!(agreement, actor: nil)
      ApplicationRecord.transaction do
        agreement.lock!
        agreement.agreement_bills.update_all(held: true)
        Bill.where(agreement_id: agreement.id, status: "canceled").update_all(status: "scheduled", updated_at: Time.current)
        CreditUse.consume!(agreement, actor, Time.current)
        agreement.update!(state: "awaiting_effectuation", broken_at: nil, break_kind: nil, closed_at: nil, reason: nil, reactivated_at: Time.current)
        AgreementEvent.log!(agreement, "reactivated", user: actor, data: { "from" => "before_effectuation" })
        Change.create!(tenant_id: agreement.tenant_id, user: actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "broken", after: "awaiting_effectuation", note: "reativado")
      end
    end

    # Título único: o pagamento ao título da quebra até o fim do prazo do título que quebrou o acordo desfaz o título da quebra e traz de volta os títulos de acordo.
    def single_title?(agreement, pay_date)
      return false unless agreement.state_broken? && agreement.break_kind == "after_effectuation" && agreement.break_form == "single_title" && enabled?(agreement)

      released = Bill.where(agreement_id: agreement.id, status: "canceled", kind: "agreement").to_a
      return false if released.empty?

      trigger = released.min_by { |bill| [ bill.due_date, bill.id ] }
      return false unless pay_date <= agreement.deadline_for(trigger, agreement.break_days)
      return false if PaymentPromiseBill.where(bill_id: released.map(&:id), held: true).exists? || AgreementBill.where(bill_id: released.map(&:id), held: true).exists?

      true
    end

    def restore_single_title!(agreement, actor: nil)
      ApplicationRecord.transaction do
        agreement.lock!
        quitted = Bill.where(agreement_id: agreement.id, kind: "break").to_a
        Bill.where(id: quitted.map(&:id)).update_all(status: "canceled", updated_at: Time.current)
        Bill.where(agreement_id: agreement.id, status: "canceled", kind: "agreement").update_all(status: "active", updated_at: Time.current)
        reopen!(agreement, actor, "single_title")
      end
    end

    # Forma "parcelas seguem": depois do pagamento, se o acordo não quebraria mais na data da quebra, ele volta a ativo.
    def after_payment!(agreement, actor: nil)
      return unless agreement.state_broken? && agreement.break_kind == "after_effectuation" && agreement.break_form == "installments_follow" && enabled?(agreement)

      return if Breaker.installments_cause(agreement, agreement.broken_at.to_date)

      ApplicationRecord.transaction { reopen!(agreement, actor, "installments_follow") }
    end

    def reopen!(agreement, actor, from)
      agreement.update!(state: "active_on_time", broken_at: nil, break_kind: nil, break_form: nil, broken_after_effectuation: false, reactivated_at: Time.current, reason: nil, closed_at: nil)
      AgreementEvent.log!(agreement, "reactivated", user: actor, data: { "from" => from })
      Change.create!(tenant_id: agreement.tenant_id, user: actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "broken", after: "active_on_time", note: "reativado")
      BrokeFlag.sync!(agreement)
    end
  end
end
