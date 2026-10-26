module Agreements
  # A decisão do gestor sobre um estorno à espera (11, R233, AH2, AJ1): quem tem "administrar acordos", com motivo, escolhe entre reabrir pela regra base, criar um título de estorno,
  # lançar no crédito do contrato (negativo, se preciso, compensado com o próximo crédito) ou reverter o acordo. A opção que o estado atual não permite não aparece. A decisão vale
  # na data em que é tomada, sobre o estado atual; o recuperado do estorno entra no mês da decisão (R64, AL1). O crédito que o pagamento gerou volta de bloqueado a disponível.
  class WaitDecision
    def initialize(actor) = @actor = actor

    # As decisões que o estado atual permite.
    def options(wait)
      list = []
      list << "reopen" if allocated(wait).positive?
      list << "reversal_title" if wait.agreement
      list << "credit"
      list << "revert" if wait.agreement && Reversion::REVERTIBLE.include?(wait.agreement.state) && !wait.agreement.reversing?
      list
    end

    def decide!(wait, decision, note, today: Date.current)
      note = note.to_s.strip
      raise Refused, I18n.t("agreements.waits.note_required") if note.empty?
      raise Refused, I18n.t("agreements.refused.reason_too_long", max: Canceller::MAX_REASON) if note.length > Canceller::MAX_REASON

      ApplicationRecord.transaction do
        wait.lock!
        raise Refused, I18n.t("agreements.waits.already_decided") unless wait.state_waiting?
        raise Refused, I18n.t("agreements.waits.option_unavailable") unless options(wait).include?(decision)

        @note = note
        case decision
        when "reopen" then apply_reopen(wait, today)
        when "reversal_title" then apply_reversal_title(wait, today)
        when "credit" then apply_credit(wait, today)
        when "revert" then apply_revert(wait, today)
        end
        record_reversal(wait, today) unless decision == "revert"
        unblock(wait) unless decision == "revert"
        wait.update!(state: "decided", decision: decision, decided_by: @actor, decided_at: Time.current, note: note)
        agreement = wait.agreement
        AgreementEvent.log!(agreement, "reversal_decided", user: @actor, data: { "decision" => decision, "amount_cents" => wait.amount_cents, "note" => note }) if agreement
        Change.record!(tenant_id: wait.tenant_id, user: @actor, subject_type: "payment", subject_id: wait.payment_id, event: "reversal_decided", after: decision, note: note)
      end
      Broadcast.changed(wait.tenant, [ wait.agreement&.customer_id ].compact)
      wait
    end

    private
      # O que o pagamento ainda tem alocado em títulos (o que dá para reabrir).
      def allocated(wait) = PaymentAllocation.where(payment_id: wait.payment_id).group(:bill_id).sum(:amount_cents).values.select(&:positive?).sum

      def apply_reopen(wait, today)
        left = wait.amount_cents
        order = PaymentAllocation.where(payment_id: wait.payment_id).group(:bill_id).maximum(:id).sort_by { |_, id| -id }.map(&:first)
        reopened = []
        order.each do |bill_id|
          break unless left.positive?

          bill = Bill.find(bill_id)
          result = AllocationUndo.call(wait.payment, bill, cents: left)
          next if result.cash.zero?

          left -= result.cash
          reopened << bill
        end
        reopened.each do |bill|
          next unless bill.reload.ledgered? && bill.active?

          bill.update!(composition: (bill.composition || {}).merge("reopened_on" => today.iso8601)) if bill.agreement&.frozen_policy("bank_reversal") != "since_due"
        end
        agreements = Agreement.where(id: reopened.filter_map(&:agreement_id).uniq)
        agreements.each { |agreement| %w[settled renegotiated].include?(agreement.state) ? ClosedReopening.call(agreement, on: today) : Standing.refresh!(agreement, today: today) }
      end

      def apply_reversal_title(wait, today)
        agreement = wait.agreement
        original = agreement.agreement_bills.includes(:bill, :contract).min_by { |item| [ item.bill.due_date, item.bill_id ] }
        items = [ { "bill_id" => original.bill_id, "component" => "principal", "cents" => wait.amount_cents } ]
        ReversalTitles.create!(agreement, items: items, contract: original.contract, action_on: wait.reversed_on, processed_on: today, reason: "manager")
      end

      # Lançamento do gestor no crédito do contrato: negativo, e pode deixar o saldo negativo (AH2).
      def apply_credit(wait, _today)
        CreditBook.take!(wait.contract_id, wait.amount_cents, kind: "manager", reason: "manager_entry", user: @actor, payment_id: wait.payment_id, note: "estorno de #{wait.payment.identifier}")
      end

      def apply_revert(wait, today)
        Reversion.new(@actor).open!(wait.agreement, @note, today: today)
      end

      # O recuperado do estorno decidido entra no mês da decisão (R64, AL1).
      def record_reversal(wait, today)
        payment = wait.payment
        PaymentReversal.create!(tenant_id: wait.tenant_id, channel_id: payment.channel_id, payment: payment, identifier: "DEC-#{wait.id}", reversed_on: today, amount_cents: wait.amount_cents,
                                from_bill_cents: wait.amount_cents, reason: "decisão do gestor sobre estorno à espera")
      end

      def unblock(wait)
        held = Credit.where(contract_id: wait.contract_id, bucket: "blocked", payment_id: wait.payment_id).sum(:amount_cents)
        CreditBook.move!(wait.contract_id, from: "blocked", to: "available", cents: held, reason: "reversal_waiting", user: @actor, payment_id: wait.payment_id) if held.positive?
      end
  end
end
