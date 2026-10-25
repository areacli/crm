module Discrepancies
  # Trata uma divergência de valor aberta (R99): nota obrigatória e uma escolha, manter (nada muda) ou aplicar o valor informado. Aplicar só
  # existe para divergência da política "manter e registrar" em título não pago e produz os efeitos da política "seguir" (R94, R95): versão
  # nova do valor e, se o saldo zera, o título passa a pago. A permissão 6 já foi conferida pela política, no credor da divergência.
  class Handler
    def initialize(actor) = @actor = actor

    def call(discrepancy, note:, choice:)
      note = note.to_s.strip
      raise Refused, I18n.t("discrepancies.note_required") if note.empty?
      raise Refused, I18n.t("discrepancies.invalid_choice") unless ValueDiscrepancy.choices.key?(choice.to_s)

      ApplicationRecord.transaction do
        # Trava a divergência e o título: duas pessoas tratando a mesma divergência, ou duas divergências do mesmo título, não se cruzam.
        discrepancy.lock!
        bill = Bill.lock.find(discrepancy.bill_id)
        raise Refused, I18n.t("discrepancies.already_handled") unless discrepancy.open?

        apply(discrepancy, bill) if choice.to_s == "apply"
        discrepancy.update!(status: :handled, choice: choice, note: note[0, 500], handled_by: @actor, handled_at: Time.current)
        Change.create!(tenant_id: discrepancy.tenant_id, user: @actor, subject_type: "bill", subject_id: bill.id, event: "discrepancy_handled", field: "choice",
                       after: choice.to_s)
      end
      discrepancy
    end

    private
      def apply(discrepancy, bill)
        raise Refused, I18n.t("discrepancies.value_changed") if bill.amount_cents != discrepancy.previous_cents
        raise Refused, I18n.t("discrepancies.cannot_apply") unless discrepancy.effect_kept? && !bill.paid?

        reported = discrepancy.reported_cents
        before = bill.amount_cents
        bill.amount_cents = reported
        Change.create!(tenant_id: bill.tenant_id, user: @actor, subject_type: "bill", subject_id: bill.id, event: "updated", field: "amount_cents",
                       before: before.to_s, after: reported.to_s)
        # Quita só o título em cobrança; o retirado muda de valor e segue retirado.
        if bill.active? && reported <= bill.paid_cents
          bill.status = :paid
          bill.paid_on = bill.payments.applied.maximum(:paid_on) || Date.current
          Change.create!(tenant_id: bill.tenant_id, user: @actor, subject_type: "bill", subject_id: bill.id, event: "settled_by_value", field: "status",
                         before: "active", after: "paid")
        end
        bill.save!
        BillValueVersion.create!(tenant_id: bill.tenant_id, bill: bill, amount_cents: reported, import_id: discrepancy.import_id, user: @actor)
      end
  end
end
