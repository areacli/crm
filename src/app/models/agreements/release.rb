module Agreements
  # O fim do acordo que ainda não foi efetivado (11, R235): cancelamento automático (R222, R232, R240), quebra antes da efetivação (R234, R238) e o cancelamento
  # manual de uma proposta já aceita. Os títulos originais nunca deixaram de valer: ficam livres, com o que foi pago da entrada alocado neles (R226) pela política
  # (AC10: pela composição da entrada, ou do mais antigo para o mais novo); a parte que cobriu a mora da entrada vai aos originais, do mais antigo para o mais novo
  # (AE10). Os títulos de acordo são cancelados e o crédito usado volta disponível ao contrato de onde saiu (R223). O pagamento feito com crédito na entrada é estornado.
  class Release
    def initialize(actor = nil) = @actor = actor

    # `to`: "canceled" ou "broken"; `event`: o evento do histórico; `reason`: o motivo mostrado ao operador.
    def call(agreement, to:, reason:, event:, on: Date.current, break_kind: nil)
      ApplicationRecord.transaction do
        agreement.lock!
        return agreement unless agreement.state_awaiting_effectuation?

        entry = agreement.entry_title
        reverse_credit_payments(agreement, entry, on)
        move_entry_payments(agreement, entry, on) if entry
        Bill.where(agreement_id: agreement.id).where.not(status: "paid").update_all(status: "canceled", updated_at: Time.current)
        agreement.agreement_bills.update_all(held: false)
        CreditUse.release!(agreement, user: @actor)
        attributes = { state: to, reason: reason, closed_at: Time.current }
        attributes.merge!(broken_at: Time.current, break_kind: break_kind || "before_effectuation") if to == "broken"
        agreement.update!(attributes)
        AgreementEvent.log!(agreement, event, user: @actor, data: { "reason" => reason })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "awaiting_effectuation", after: to, note: reason)
      end
      agreement
    end

    private
      # O pagamento da entrada feito com crédito é estornado (o crédito volta pelo `CreditUse.release!`).
      def reverse_credit_payments(agreement, entry, on)
        channel = PaymentChannel.find_by(tenant_id: agreement.tenant_id, code: CreditUse::CHANNEL_CODE) or return
        Payment.where(agreement_id: agreement.id, channel_id: channel.id).where("reversed_cents < amount_cents").find_each do |payment|
          undo_allocations(payment, entry)
          left = payment.amount_cents - payment.reversed_cents
          PaymentReversal.create!(tenant_id: payment.tenant_id, channel_id: channel.id, payment: payment, identifier: "EST-#{payment.identifier}", reversed_on: on, amount_cents: left,
                                  from_credit_cents: 0, from_bill_cents: left, reason: "acordo desfeito antes da efetivação")
          payment.update!(reversed_cents: payment.amount_cents, status: "cancelled")
        end
      end

      # Desfaz a alocação de um pagamento no título (linhas negativas) e tira o principal abatido do pago. Devolve { componente => centavos } do que estava alocado.
      def undo_allocations(payment, bill)
        parts = PaymentAllocation.where(payment_id: payment.id, bill_id: bill.id).group(:component).sum(:amount_cents).select { |_, cents| cents.positive? }
        parts.each { |component, cents| PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: -cents) }
        Abatement.where(payment_id: payment.id, bill_id: bill.id).group(:kind, :component).sum(:amount_cents).select { |_, cents| cents.positive? }.each do |(kind, component), cents|
          Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: kind, component: component, amount_cents: -cents)
        end
        bill.update!(paid_cents: 0, paid_on: nil)
        parts
      end

      # O que os pagamentos reais cobriram da entrada volta aos originais (AC10).
      def move_entry_payments(agreement, entry, on)
        originals = agreement.agreement_bills.includes(:bill).sort_by { |item| [ item.bill.due_date, item.bill_id ] }.map(&:bill)
        payments = Payment.joins(:channel).where(id: PaymentAllocation.where(bill_id: entry.id).select(:payment_id))
                          .where.not(payment_channels: { code: CreditUse::CHANNEL_CODE }).includes(:channel).order(:paid_on, :id)
        settlement = Charges::Settlement.for(agreement.tenant, today: on)
        settlement&.preload(originals.map(&:id))
        items = entry.composition.fetch("items", [])
        policy = agreement.frozen_policy("partial_down_payment")
        payments.each do |payment|
          parts = undo_allocations(payment, entry)
          by_composition = policy == "by_composition" ? map_to_originals(parts.except("late"), items) : {}
          rest = parts.sum { |_, cents| cents } - by_composition.values.sum { |components| components.values.sum }
          by_composition.each { |bill_id, components| allocate(payment, originals.find { |bill| bill.id == bill_id }, components) }
          spread(payment, originals, rest, settlement, on) if rest.positive?
        end
      end

      # Cada original recebe o que o pagamento já tinha coberto da parte dele: em cada componente, nos pedaços da composição da entrada, do primeiro para o último.
      def map_to_originals(parts, items)
        mapped = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        parts.each do |component, cents|
          items.select { |item| item["component"] == component }.each do |item|
            take = [ cents, item["cents"] ].min
            next unless take.positive?

            mapped[item["bill_id"]][component] += take
            cents -= take
          end
        end
        mapped
      end

      # O resto vai aos originais do mais antigo para o mais novo, encargos antes do principal, pela alocação da baixa (R226); o que sobrar vira crédito do contrato.
      def spread(payment, originals, cents, settlement, on)
        originals.each do |bill|
          break if cents <= 0
          next unless bill.active? || bill.renegotiated?

          balance = [ bill.amount_cents - bill.paid_cents, 0 ].max
          next if balance.zero?

          due = settlement&.due(bill.id, on, balance) || { "principal" => balance }
          due["principal"] = [ due.fetch("principal", 0), balance ].min
          parts = Payments::Allocation.distribute(due, cents)
          allocate(payment, bill, parts)
          settlement&.record(bill.id, on, parts)
          cents -= parts.values.sum
        end
        return unless cents.positive?

        Credit.create!(tenant_id: payment.tenant_id, contract_id: originals.first.contract_id, payment: payment, user: @actor, kind: :entry, amount_cents: cents, reason: :excess, note: "acordo desfeito")
      end

      def allocate(payment, bill, components)
        components.each { |component, cents| PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: cents) if cents.positive? }
        paid = bill.paid_cents + components.fetch("principal", 0)
        bill.update!(paid_cents: paid, status: (paid >= bill.amount_cents ? "paid" : bill.status), paid_on: (paid >= bill.amount_cents ? payment.paid_on : bill.paid_on))
      end
  end
end
