module Agreements
  # Cancelar é reverter (11, R239, DA24, N9): o acordo aceito, inclusive quebrado ou quitado, é desfeito como se a renegociação não tivesse acontecido, em dois passos registrados,
  # por quem tem "administrar acordos". Primeiro passo (`open!`): o acordo fica **em reversão** (marca), as promessas e as propostas sobre os títulos dele são canceladas, os cálculos
  # de quitação perdem a validade e as liquidações são estornadas, sem arquivo do canal (o dinheiro continua entrado e vira **crédito do contrato aguardando alocação**). Entre os
  # passos, a tarefa diária não quebra o acordo, os encargos e a contagem dos prazos ficam parados (X3) e o crédito aguardando alocação não se aloca nem se transfere. Segundo passo
  # (`conclude!`): os títulos de acordo e de estorno são cancelados, os originais voltam a ativos como estavam antes do aceite (com os encargos de todo o período) e o crédito usado volta
  # disponível ao contrato de onde saiu. O gestor pode **desistir** (`desist!`, V4) em vez de concluir. O crédito aguardando alocação é do gestor: aloca em título do mesmo contrato
  # (`allocate_credit!`) ou transfere a outro contrato (`Payments::CreditTransfer`).
  class Reversion
    REVERTIBLE = %w[awaiting_effectuation active_on_time active_late settled broken].freeze
    PROMISE_REASON = "acordo em reversão".freeze
    LIQUIDATION_PREFIX = "LIQ".freeze

    def initialize(actor) = @actor = actor

    # --- Passo 1: abrir a reversão ---
    def open!(agreement, reason, today: Date.current)
      reason = clean_reason(reason)
      ApplicationRecord.transaction do
        agreement.lock!
        raise Refused, I18n.t("agreements.reversion.not_revertible") unless REVERTIBLE.include?(agreement.state) && !agreement.reversing?

        titles = agreement.titles.to_a
        reversal_titles = agreement.reversal_titles.to_a
        guard_new_agreements!(titles + reversal_titles)
        ids = (titles + reversal_titles).map(&:id)
        PromiseCancellation.cancel(ids, @actor, PROMISE_REASON)
        cancel_proposals(ids)
        agreement.settlements.where(expired_at: nil).update_all(expired_at: Time.current)
        liquidations = reverse_liquidations(agreement, titles, today)
        spans = agreement.frozen_spans + [ { "kind" => "reversal", "from" => today.iso8601, "to" => nil } ]
        reversion = { "liquidations" => liquidations, "opened_on" => today.iso8601 }
        agreement.update!(reversing_since: Time.current, reversal_reason: reason, reversal_by: @actor, reverted_at: nil, terms: agreement.terms.merge("frozen" => spans, "reversion" => reversion))
        AgreementEvent.log!(agreement, "reversion_opened", user: @actor, data: { "reason" => reason, "liquidations" => liquidations.size })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "reversion_opened", note: reason)
      end
      Broadcast.changed(agreement.tenant, [ agreement.customer_id ])
      agreement
    end

    # --- Passo 2: concluir (cancelar) ---
    def conclude!(agreement, today: Date.current)
      ApplicationRecord.transaction do
        agreement.lock!
        raise Refused, I18n.t("agreements.reversion.not_reversing") unless agreement.reversing?

        released = release_credit(agreement)
        cancel_titles(agreement)
        previous_ids = Bill.where(id: agreement.agreement_bills.select(:bill_id), status: "renegotiated").where.not(agreement_id: nil).distinct.pluck(:agreement_id)
        reactivate_originals(agreement)
        reassess_previous(previous_ids, agreement, today)
        spans = close_spans(agreement, today)
        agreement.update!(state: "canceled", reverted_at: Time.current, closed_at: Time.current, reason: agreement.reversal_reason, terms: agreement.terms.merge("frozen" => spans))
        AgreementEvent.log!(agreement, "canceled", user: @actor, data: { "reason" => agreement.reversal_reason, "reverted" => true, "credit_restored_cents" => released })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "reversing", after: "canceled", note: agreement.reversal_reason)
        BrokeFlag.sync!(agreement)
      end
      Broadcast.changed(agreement.tenant, [ agreement.customer_id ])
      agreement
    end

    # --- Desistir (V4) ---
    # Padrão ("reapply_all"): reaplica as liquidações estornadas e os pagamentos dirigidos ao acordo no intervalo, e os encargos do período suspenso não voltam. Alternativa
    # ("reapply_settlements"): reaplica só as liquidações; os pagamentos do intervalo seguem como crédito para o gestor alocar, e os encargos do período voltam.
    def desist!(agreement, today: Date.current)
      ApplicationRecord.transaction do
        agreement.lock!
        raise Refused, I18n.t("agreements.reversion.not_reversing") unless agreement.reversing?

        all = Policies.value(agreement.tenant.setting, "reversal_withdrawal") == "reapply_all"
        reapply_liquidations(agreement)
        reapply_interval_payments(agreement, today) if all
        spans = close_spans(agreement, today, keep_charges: !all)
        terms = agreement.terms.merge("frozen" => spans).except("reversion")
        agreement.update!(reversing_since: nil, reversal_reason: nil, reversal_by: nil, terms: terms)
        AgreementEvent.log!(agreement, "reversion_desisted", user: @actor, data: { "policy" => all ? "reapply_all" : "reapply_settlements" })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "reversion_desisted", note: all ? "reaplica tudo" : "reaplica as liquidações")
      end
      Standing.refresh!(agreement.reload, today: today)
      Broadcast.changed(agreement.tenant, [ agreement.customer_id ])
      agreement
    end

    # --- O crédito aguardando alocação (R239) ---
    # Aloca `cents` do crédito aguardando alocação do contrato num título do mesmo contrato (A6, RV2-5). O pagamento vale com a data mais tardia entre a entrada do dinheiro e a
    # criação do título (para encargos, tolerância e quebra, AA7); a alocação nunca reativa acordo nem dá desconto de antecipação (AB3). O gestor escolhe o título.
    def allocate_credit!(contract, bill, cents, today: Date.current)
      raise Refused, I18n.t("agreements.reversion.other_contract") unless bill.contract_id == contract.id
      raise Refused, I18n.t("agreements.reversion.invalid_amount") unless cents.to_i.positive?

      ApplicationRecord.transaction do
        contract.lock!
        raise Refused, I18n.t("agreements.reversion.marked") if marked?(contract)
        raise Refused, I18n.t("agreements.reversion.above_awaiting", available: Money.format(CreditBook.balance(contract.id, "awaiting"))) if cents > CreditBook.balance(contract.id, "awaiting")
        raise Refused, I18n.t("agreements.reversion.bill_not_open") unless bill.active? || bill.scheduled?

        money_on = money_date(contract)
        date = [ money_on, bill.created_at.to_date ].max
        agreement = bill.agreement || bill.origin_agreement
        tolerance = agreement&.tolerance_spec
        payment = Payment.create!(tenant_id: bill.tenant_id, channel: CreditUse.channel_for(bill.tenant), identifier: "ALOC-#{SecureRandom.hex(5)}", document: bill.customer.document,
                                  bill_number: bill.number, bill: bill, paid_on: date, amount_cents: cents, payment_method: "other", status: "applied")
        outcome = TitleSettler.pay!(payment, bill, cents, date, tolerance: tolerance, early: false)
        raise Refused, I18n.t("agreements.reversion.nothing_applied") if outcome.applied.zero?

        payment.update!(applied_cents: outcome.applied, credit_cents: outcome.excess)
        CreditBook.take!(contract.id, outcome.applied, kind: "used", reason: "allocated", bucket: "awaiting", user: @actor, bill_id: bill.id, agreement_id: agreement&.id, note: bill.number)
        Change.create!(tenant_id: bill.tenant_id, user: @actor, subject_type: "bill", subject_id: bill.id, event: "credit_allocated", after: outcome.applied.to_s)
        Standing.refresh!(bill.agreement, today: today) if bill.agreement&.running? || bill.agreement&.state_settled?
        outcome
      end
    end

    # A marca "em reversão" em algum acordo dos títulos do contrato: enquanto dura, o crédito aguardando alocação do contrato não se aloca nem se transfere.
    def self.marked?(contract)
      Agreement.where(id: AgreementBill.where(contract_id: contract.id).select(:agreement_id)).where.not(reversing_since: nil).where(reverted_at: nil).exists?
    end

    private
      def marked?(contract) = self.class.marked?(contract)

      def clean_reason(text)
        text = text.to_s.strip
        raise Refused, I18n.t("agreements.reversion.reason_required") if text.empty?
        raise Refused, I18n.t("agreements.refused.reason_too_long", max: Canceller::MAX_REASON) if text.length > Canceller::MAX_REASON

        text
      end

      # Acordo com título renegociado num acordo novo aceito, ou acordo novo aguardando efetivação sobre os títulos: só se reverte depois de revertido o novo (R239, AG5).
      def guard_new_agreements!(bills)
        ids = bills.map(&:id)
        blocking = AgreementBill.joins(:agreement).where(bill_id: ids).where(agreements: { state: %w[awaiting_effectuation active_on_time active_late settled broken renegotiated] })
        raise Refused, I18n.t("agreements.reversion.new_agreement", number: blocking.first.agreement.number) if blocking.exists?
      end

      def cancel_proposals(ids)
        Agreement.where(id: AgreementBill.where(bill_id: ids, held: true).select(:agreement_id)).proposals.lock.each do |proposal|
          Canceller.new(@actor).cancel(proposal, PROMISE_REASON)
        end
      end

      # R239, passo 1: estorna a liquidação de cada pagamento aos títulos de acordo: as alocações e os abatimentos viram linhas negativas, o dinheiro continua entrado e passa a crédito
      # aguardando alocação do contrato do título, e o recuperado do mês cai (R64). Devolve o que foi desfeito, para a desistência reaplicar.
      def reverse_liquidations(agreement, titles, today)
        bill_ids = titles.map(&:id)
        payment_ids = (PaymentAllocation.where(bill_id: bill_ids).distinct.pluck(:payment_id) | Abatement.where(bill_id: bill_ids).distinct.pluck(:payment_id))
        credit_paid = Hash.new(0)
        list = []
        Payment.where(id: payment_ids).order(:paid_on, :id).each do |payment|
          cash_total = 0
          titles.each do |bill|
            result = AllocationUndo.call(payment, bill.reload, abatements: true)
            next if result.parts.empty? && result.abated.empty?

            cash = result.cash
            cash_total += cash
            CreditBook.add!(bill.contract_id, cash, reason: "settlement_reversed", bucket: "awaiting", payment_id: payment.id, agreement_id: agreement.id, note: bill.number, user: @actor) if cash.positive?
            credit_paid[bill.contract_id] += cash if payment.channel.code == CreditUse::CHANNEL_CODE
            list << { "payment_id" => payment.id, "bill_id" => bill.id, "contract_id" => bill.contract_id, "parts" => result.parts, "abated" => result.abated, "cash" => cash }
          end
          next unless cash_total.positive?

          payment.update!(moved_to_credit_cents: payment.moved_to_credit_cents + cash_total)
          PaymentReversal.create!(tenant_id: payment.tenant_id, channel_id: payment.channel_id, payment: payment, identifier: "#{LIQUIDATION_PREFIX}-#{agreement.number}-#{payment.id}", reversed_on: today,
                                  amount_cents: cash_total, from_bill_cents: cash_total, reason: "liquidação estornada na reversão de #{agreement.number}")
        end
        agreement.terms["credit_paid"] = credit_paid.transform_keys(&:to_s)
        list
      end

      # A desistência reaplica as liquidações estornadas: as alocações e os abatimentos voltam, o crédito aguardando alocação desse pagamento sai e o recuperado volta a ser o que era.
      def reapply_liquidations(agreement)
        agreement.terms.dig("reversion", "liquidations").to_a.each do |item|
          payment = Payment.find(item["payment_id"])
          bill = Bill.find(item["bill_id"])
          item["parts"].each { |component, cents| PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: cents) }
          item["abated"].each { |kind, component, cents| Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: kind, component: component, amount_cents: cents) }
          face = item["parts"].sum { |component, cents| AllocationUndo.face?(bill, component) ? cents : 0 } + item["abated"].sum { |_, component, cents| AllocationUndo.face?(bill, component) ? cents : 0 }
          paid = bill.paid_cents + face
          bill.update!(paid_cents: paid, status: (paid >= bill.amount_cents ? "paid" : bill.status), paid_on: (paid >= bill.amount_cents ? payment.paid_on : bill.paid_on))
          CreditBook.take!(item["contract_id"], item["cash"], kind: "used", reason: "allocated", bucket: "awaiting", user: @actor, payment_id: payment.id, agreement_id: agreement.id, note: "reaplicada") if item["cash"].positive?
          payment.update!(moved_to_credit_cents: [ payment.moved_to_credit_cents - item["cash"], 0 ].max)
        end
        PaymentReversal.where(tenant_id: agreement.tenant_id).where("identifier LIKE ?", "#{LIQUIDATION_PREFIX}-#{agreement.number}-%").delete_all
      end

      # O que chegou ao acordo durante a marca (crédito aguardando alocação com o motivo "durante a reversão") é reaplicado aos títulos em aberto, do mais antigo para o mais novo.
      def reapply_interval_payments(agreement, today)
        entries = Credit.where(agreement_id: agreement.id, bucket: "awaiting", reason: "during_reversal").where("amount_cents > 0").order(:occurred_at, :id).to_a
        entries.each do |entry|
          payment = Payment.find(entry.payment_id)
          left = [ entry.amount_cents, CreditBook.balance(entry.contract_id, "awaiting") ].min
          agreement.titles.where(status: "active").each do |bill|
            break unless left.positive?

            outcome = TitleSettler.pay!(payment, bill.reload, left, payment.paid_on, tolerance: agreement.tolerance_spec)
            next if outcome.applied.zero?

            CreditBook.take!(entry.contract_id, outcome.applied, kind: "used", reason: "allocated", bucket: "awaiting", user: @actor, payment_id: payment.id, agreement_id: agreement.id, bill_id: bill.id)
            left -= outcome.applied
          end
          CreditBook.move!(entry.contract_id, from: "awaiting", to: "available", cents: left, reason: "allocated", user: @actor, payment_id: payment.id, agreement_id: agreement.id) if left.positive? && left == CreditBook.balance(entry.contract_id, "awaiting")
        end
      end

      # Fecha o intervalo congelado da reversão; na desistência com a alternativa, os encargos do período voltam (o intervalo deixa de descontar os encargos, mas continua parando a contagem).
      def close_spans(agreement, today, keep_charges: false)
        agreement.frozen_spans.map do |span|
          next span unless span["kind"] == "reversal" && span["to"].nil?

          span.merge("to" => today.iso8601, "keep_charges" => keep_charges)
        end
      end

      # O crédito usado volta disponível ao contrato de onde saiu (R223, R239): menos o pago com crédito na entrada (que já voltou como aguardando alocação) e o valor original dos
      # títulos de estorno da origem do crédito (AC4).
      def release_credit(agreement)
        used = Credit.where(agreement_id: agreement.id, kind: "used", bucket: "available", bill_id: nil).group(:contract_id).sum(:amount_cents)
        credit_paid = agreement.terms.fetch("credit_paid", {})
        from_reversal = agreement.reversal_titles.where(status: "active").where("jsonb_exists(composition, 'credit_origin')").to_a.group_by(&:contract_id).transform_values { |bills| bills.sum { |bill| bill.composition["credit_origin"].to_i } }
        restored = 0
        used.each do |contract_id, cents|
          back = -cents - credit_paid.fetch(contract_id.to_s, 0) - from_reversal.fetch(contract_id, 0)
          next unless back.positive?

          CreditBook.add!(contract_id, back, reason: "agreement", kind: "restored", user: @actor, agreement_id: agreement.id, note: agreement.number)
          restored += back
        end
        restored
      end

      def cancel_titles(agreement)
        agreement.titles.where.not(status: "canceled").update_all(status: "canceled", updated_at: Time.current)
        agreement.reversal_titles.where.not(status: "canceled").each do |bill|
          cancel_reversal_title(bill)
        end
        agreement.agreement_bills.update_all(held: false)
      end

      # O título de estorno é cancelado na reversão (R239, AG8, AC4): o que foi pago nele volta como crédito aguardando alocação e, se nasceu de pagamento anterior à montagem, a
      # parte volta ao título original.
      def cancel_reversal_title(bill)
        payment_ids = PaymentAllocation.where(bill_id: bill.id).distinct.pluck(:payment_id)
        Payment.where(id: payment_ids).find_each do |payment|
          result = AllocationUndo.call(payment, bill.reload, abatements: true)
          next if result.cash.zero?

          CreditBook.add!(bill.contract_id, result.cash, reason: "settlement_reversed", bucket: "awaiting", payment_id: payment.id, note: bill.number, user: @actor)
          payment.update!(moved_to_credit_cents: payment.moved_to_credit_cents + result.cash)
        end
        origin = bill.composition["origin_bill_id"]
        if origin
          original = Bill.find_by(id: origin)
          original&.update!(paid_cents: [ original.paid_cents - bill.composition["origin_paid_cents"].to_i, 0 ].max) if bill.composition["origin_paid_cents"].to_i.positive?
        end
        bill.update!(status: "canceled")
      end

      # Os originais voltam a ativos como estavam antes do aceite (R239); os que o acordo renegociou saem de renegociados.
      def reactivate_originals(agreement)
        Bill.where(id: agreement.agreement_bills.select(:bill_id), status: "renegotiated").update_all(status: "active", updated_at: Time.current)
      end

      # R239, R250, AG5: o acordo revertido era o novo de um acordo sobre acordo: o anterior volta ao estado que tinha, é reavaliado com os títulos que voltam, e a contagem da tolerância e dos
      # dias de quebra dos títulos dele que foram renegociados fica parada da efetivação do novo ao cancelamento (os encargos correm desde o vencimento, AB6).
      def reassess_previous(ids, reverted, today)
        from = (reverted.effectuated_at || Time.current).to_date
        Agreement.where(id: ids).each do |previous|
          spans = previous.frozen_spans + [ { "kind" => "reversal", "from" => from.iso8601, "to" => today.iso8601, "keep_charges" => true } ]
          state = previous.state_renegotiated? ? (previous.broken_after_effectuation ? "broken" : "active_on_time") : previous.state
          previous.update!(state: state, closed_at: nil, terms: previous.terms.merge("frozen" => spans))
          AgreementEvent.log!(previous, "reopened", user: @actor, data: { "from" => "renegotiated", "reverted" => reverted.number })
          Standing.refresh!(previous.reload, today: today)
        end
      end

      def money_date(contract)
        entry = Credit.where(contract_id: contract.id, bucket: "awaiting").where("amount_cents > 0").order(:occurred_at, :id).first
        payment = entry&.payment
        payment&.paid_on || entry&.occurred_at&.to_date || Date.current
      end
  end
end
