module Agreements
  # Os efeitos do estorno bancário sobre acordos e crédito (11, R233 e a tabela "Estornos e reversões que o CRM resolve", R62): o `Payments::ReversalProcessor` trata em lote o estorno
  # comum (o título volta a aberto, o crédito cai), e este objeto decide, linha a linha, o que não é comum:
  # - pagamento a título de acordo cujo acordo está em reversão, ou a título que a tabela não cobre: fica **à espera do gestor**, sem efeito, e o crédito que o pagamento gerou fica bloqueado;
  # - pagamento aplicado a título original que já foi renegociado num acordo efetivado (AF3): o original não volta à cobrança, nasce um **título de estorno** fora do acordo;
  # - crédito do pagamento que já foi usado (num acordo, num título pela ficha) ou transferido a outro contrato: segue a linha do título em que foi usado, ou sai de quem recebeu;
  # - original preso a acordo aguardando efetivação: o acordo é cancelado com "valor do título mudou" (R240);
  # - acordo encerrado (quitado ou renegociado) que ganhou título em aberto: o teste da soma (AE3, AF1).
  # Tudo o que mexe em mais de uma tabela roda depois da gravação em lote (`finish!`), para ler o banco já com o que o lote gravou. A conferência (`commit: false`) só conta.
  class ReversalEffects
    Route = Data.define(:kind, :reason)
    BASE = Route.new(:base, nil)

    TRUE_VALUES = [ true, "t", "true", 1 ].freeze

    attr_reader :summary

    def initialize(import, setting, summary)
      @import = import
      @tenant = import.tenant
      @setting = setting
      @summary = summary
      @positions = {}
      @pending = []
      @cancel = {} # acordo aguardando efetivação => motivo
      @reopened = {} # título de acordo reaberto => data da ação (N10)
      @touched_agreements = Set.new
    end

    # Como o estorno de uma linha é tratado: `:base` (em lote), `:wait` (espera o gestor) ou `:renegotiated_original` (título de estorno).
    def route(row)
      kind = row["bill_kind"].presence || "common"
      status = row["bill_status"]
      return Route.new(:settlement, nil) if row["agreement_id"].present? && row["ag_state"] == "settled" && Abatement.exists?(payment_id: row["payment_id"], kind: "early")
      if kind != "common" || row["agreement_id"].present?
        return wait(:in_reversion) if truthy?(row["ag_reversing"])
        return wait(:renegotiated_title) if status == "renegotiated" && row["applied_cents"].to_i.positive?
        return wait(:before_break) if status == "canceled"
        return wait(:held_by_new_agreement) if row["held_state"] == "awaiting_effectuation"
      elsif status == "renegotiated" && row["applied_cents"].to_i.positive?
        # Só o pagamento aplicado ao título antes da montagem gera título de estorno; o pagamento que virou crédito (DA8) segue a linha do crédito.
        return Route.new(:renegotiated_original, nil)
      elsif row["held_state"] == "awaiting_effectuation"
        @cancel[row["held_agreement_id"].to_i] = I18n.t("agreements.cancel_reasons.value_changed")
      end
      BASE
    end

    # O estorno do pagamento da quitação antecipada (R230, AE9): trata o pagamento inteiro, com a data da ação.
    def defer_settlement(row, amount)
      summary[:settlement_reversed] += 1
      @pending << -> { SettlementReversal.call(Payment.find(row["payment_id"]), amount, Date.iso8601(row["reversed_on"].to_s)) }
    end

    # O estorno que espera o gestor: nada muda no título nem no crédito agora (R233).
    def defer_wait(row, amount, reason)
      summary[:waiting] += 1
      summary[:waiting_cents] += amount
      @pending << -> { create_wait!(row, amount, reason) }
    end

    # Estorno de pagamento a título original já renegociado (AF3): nasce o título de estorno com o que o estorno tirou (`taken`: componente => centavos).
    def defer_reversal_title(row, taken)
      summary[:reversal_titles] += 1
      @pending << -> { create_reversal_title!(row, taken) }
    end

    # O crédito do pagamento estornado: o que ainda está disponível da origem sai em lote; o resto segue as linhas da tabela (transferido, usado) depois. Devolve o plano.
    def plan_credit(row, cents)
      payment_id = row["payment_id"].to_i
      contract_id = row["contract_id"].to_i
      position = (@positions[payment_id] ||= CreditOrigin.position(contract_id, payment_id))
      plan = CreditOrigin.plan(position, cents)
      if plan.awaiting.positive? || plan.blocked.positive? || plan.uses.any? || plan.unattributed.positive?
        summary[:credit_origin] += 1
        @pending << -> { apply_credit_plan!(row, plan) }
      end
      plan
    end

    # Registra que um título de acordo foi reaberto por estorno (N10) e que o acordo dele precisa ser reavaliado.
    def note_reopened(bill_id, agreement_id, reversed_on)
      @reopened[bill_id] = reversed_on
      @touched_agreements << agreement_id if agreement_id
    end

    # Pedidos que o tratamento do crédito faz ao fim: cancelar o acordo aguardando efetivação (V1), reavaliar um acordo, esperar o gestor.
    def request_cancel(agreement_id, reason) = (@cancel[agreement_id] = reason)

    def touch_agreement(agreement_id) = @touched_agreements << agreement_id

    def wait_credit(row, cents) = create_wait!(row.merge("bill_id" => nil), cents, "credit_unattributed")

    # Executa o que ficou para depois da gravação em lote.
    def finish!
      @pending.each(&:call)
      mark_reopened!
      cancel_held!
      reassess!
    end

    private
      def truthy?(value) = TRUE_VALUES.include?(value)

      def wait(reason) = Route.new(:wait, reason.to_s)

      # --- À espera do gestor (R233, AK2) ---
      def create_wait!(row, amount, reason)
        payment = Payment.find(row["payment_id"])
        agreement_id = row["bill_agreement_id"].presence || row["agreement_id"].presence
        contract_id = row["contract_id"].to_i
        ReversalWait.create!(tenant_id: @tenant.id, payment: payment, agreement_id: agreement_id, contract_id: contract_id, amount_cents: amount, reason: reason, reversed_on: row["reversed_on"],
                             processed_on: Date.current, details: { "bill_id" => row["bill_id"], "reversal_identifier" => row["identifier"] })
        # AK2: o crédito que o pagamento gerou fica bloqueado até a decisão.
        credit = payment.credit_cents + payment.moved_to_credit_cents - payment.credit_reversed_cents
        if credit.positive?
          position = (@positions[payment.id] ||= CreditOrigin.position(contract_id, payment.id))
          blocked = CreditBook.move!(contract_id, from: "available", to: "blocked", cents: [ credit, position.available ].min, reason: "reversal_waiting", payment_id: payment.id, agreement_id: agreement_id)
          position.available -= blocked
          # O que está aguardando alocação (pagamento recebido durante a reversão) também fica bloqueado.
          held = CreditBook.move!(contract_id, from: "awaiting", to: "blocked", cents: [ credit - blocked, position.awaiting ].min, reason: "reversal_waiting", payment_id: payment.id, agreement_id: agreement_id)
          position.awaiting -= held
        end
        agreement = Agreement.find_by(id: agreement_id)
        AgreementEvent.log!(agreement, "reversal_waiting", data: { "payment" => payment.identifier, "amount_cents" => amount, "reason" => reason }) if agreement
        Change.record!(payment, "reversal_waiting", actor: @import.user, after: amount.to_s, note: reason)
      end

      # --- Título de estorno de pagamento anterior à montagem (AF3, AG9) ---
      def create_reversal_title!(row, taken)
        original = Bill.find(row["bill_id"])
        agreement = renegotiating_agreement(original)
        return create_wait!(row, taken.values.sum, "renegotiated_title") unless agreement

        items = reversal_items(agreement, original, taken)
        title = ReversalTitles.create!(agreement, items: items, contract: original.contract, product: original.product, action_on: Date.iso8601(row["reversed_on"].to_s), processed_on: Date.current, reason: "af3")
        # A parte volta ao original se o acordo for revertido (AG8): o pago dele foi reduzido só no papel, o título de estorno guarda quanto.
        title.update!(composition: title.composition.merge("origin_bill_id" => original.id, "origin_paid_cents" => taken.fetch("principal", 0)))
      end

      def renegotiating_agreement(original)
        Agreement.where(id: AgreementBill.where(bill_id: original.id).select(:agreement_id)).where.not(effectuated_at: nil).where.not(state: "canceled").order(:id).last
      end

      # O que o estorno tirou, com os mesmos descontos do acordo que renegociou o título (AG9) e os encargos que essa parte teria acumulado até a montagem (R233).
      def reversal_items(agreement, original, taken)
        discounts = agreement.discounts_bp
        parts = taken.slice(*Charges::ORDER).dup
        accrued = accrued_until_built(agreement, original, parts.fetch("principal", 0))
        accrued.each { |component, cents| parts[component] = parts.fetch(component, 0) + cents }
        parts.filter_map do |component, cents|
          net = cents - Simulation.half_even_div(cents * discounts.fetch(component, 0).to_i, 10_000)
          { "bill_id" => original.id, "component" => component, "cents" => net } if net.positive?
        end
      end

      # Multa, juros e honorários que o principal estornado teria acumulado do vencimento do título até a montagem, pelos parâmetros congelados no acordo.
      def accrued_until_built(agreement, original, principal)
        return {} unless principal.positive? && agreement.built_on > original.due_date

        rule = Charges::AgreementRule.from_storage(agreement.terms.dig("parameters", "late_rule"))
        Charges::AgreementCalculator.call(rule, principal: principal, correction: 0, due: original.due_date, paid_on: agreement.built_on, tables: nil, fine: true).components
      end

      # --- Crédito já usado ou transferido (R62, R233, AB4) ---
      def apply_credit_plan!(row, plan)
        contract_id = row["contract_id"].to_i
        payment_id = row["payment_id"].to_i
        reversal_entry = ->(bucket, cents) { CreditBook.take!(contract_id, cents, kind: "reversal", reason: "reversed", bucket: bucket, payment_id: payment_id, user: @import.user) }
        reversal_entry.call("awaiting", plan.awaiting) if plan.awaiting.positive?
        reversal_entry.call("blocked", plan.blocked) if plan.blocked.positive?
        plan.uses.each { |entry, cents| undo_credit_use!(row, entry, cents) }
        create_wait!(row.merge("bill_id" => nil), plan.unattributed, "credit_unattributed") if plan.unattributed.positive?
      end

      def undo_credit_use!(row, entry, cents)
        if entry.transfer_out?
          # Transferido: o estorno sai do contrato de quem recebeu, com aviso aos dois lados (R55a, R62).
          CreditBook.take!(entry.related_contract_id, cents, kind: "reversal", reason: "reversed", user: @import.user, note: "estorno de crédito transferido")
          [ entry.contract_id, entry.related_contract_id ].each do |contract_id|
            Change.record!(Contract.find(contract_id), "transferred_credit_reversed", actor: @import.user, after: cents.to_s)
          end
        elsif entry.bill_id
          CreditOnBill.undo!(entry, cents, row["reversed_on"]) { |bill| note_reopened(bill.id, bill.agreement_id, Date.iso8601(row["reversed_on"].to_s)) }
        elsif entry.agreement_id
          CreditReversal.new(@import, self).call(entry, cents, row)
        else
          create_wait!(row.merge("bill_id" => nil), cents, "credit_unattributed")
        end
      end

      # --- Depois: N10, cancelamentos e reavaliação ---
      # N10 (política congelada no acordo, padrão "prazo novo"): o título de acordo reaberto por estorno conta os dias de quebra da data mais tardia entre o estorno e o vencimento. Em SQL de
      # conjunto, em lotes: com 20 mil estornos de parcela um UPDATE por título custaria minutos.
      def mark_reopened!
        @reopened.to_a.each_slice(1_000) do |slice|
          dates = slice.to_h { |bill_id, on| [ bill_id, ReversalTitles.reopened_on(on, Date.current).iso8601 ] }
          ApplicationRecord.transaction do
            Bill.where(id: dates.keys, status: "active").where.not(agreement_id: nil).preload(:agreement).each do |bill|
              next unless (bill.agreement.terms.dig("policies", "bank_reversal") || "new_term") == "new_term"

              bill.update!(composition: (bill.composition || {}).merge("reopened_on" => dates.fetch(bill.id)))
            end
          end
        end
      end

      def cancel_held!
        @cancel.each do |agreement_id, reason|
          agreement = Agreement.find_by(id: agreement_id)
          next unless agreement&.state_awaiting_effectuation?

          summary[:agreements_canceled] += 1
          Release.new.call(agreement, to: "canceled", reason: reason, event: "canceled")
        end
      end

      # A situação dos acordos tocados: o encerrado passa pelo teste da soma (um a um, é raro); os demais, em lotes (uma leitura de títulos e de eventos por lote).
      def reassess!
        ids = (@touched_agreements.to_a + Agreement.where(id: Bill.where(id: @reopened.keys).select(:agreement_id)).pluck(:id)).uniq
        ids.each_slice(500) do |slice|
          agreements = Agreement.where(id: slice).to_a
          closed, running = agreements.partition { |agreement| %w[settled renegotiated].include?(agreement.state) }
          closed.each { |agreement| ClosedReopening.call(agreement, on: Date.current) }
          Standing.refresh_many(running, today: Date.current)
        end
      end
  end
end
