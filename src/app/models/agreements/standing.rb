module Agreements
  # A situação do acordo efetivado, reavaliada depois de pagamentos, estornos e todo dia (11, R229): ativo em dia, ativo em atraso (algum título de acordo vencido há mais
  # que a tolerância e não pago) ou quitado (todos os títulos pagos, salvo restos cuja soma fique igual ou abaixo do mínimo para quebrar, que viram abatimento por mínimo,
  # P2). O mínimo só perdoa o título que recebeu algum pagamento vigente (Y1, Z2); o que não recebeu nada conta como atraso cheio e nunca é perdoado. Também depois da
  # quebra o acordo pode ficar quitado (AA11).
  #
  # `verdict` decide sem gravar, sobre títulos e `Ledger`s já lidos (a tarefa diária e a confirmação avaliam lotes de acordos de uma vez); `refresh!` lê e grava um acordo.
  module Standing
    # `state`: a situação nova; `rests`: os restos que o mínimo perdoa, quando o acordo quita com eles ({ título => devido }).
    Verdict = Data.define(:state, :event, :rests)

    module_function

    # Lê e grava um acordo. `payment_id`: o pagamento que o abatimento por mínimo cita.
    def refresh!(agreement, today: Date.current, payment_id: nil)
      agreement.reload
      titles, ledgers = LedgerLoader.new(agreement.tenant, today: today).for_agreements([ agreement ])
      verdict = verdict(agreement, titles.fetch(agreement.id, []), ledgers, today)
      apply!(agreement, verdict, today: today, payment_id: payment_id) if verdict
      agreement
    end

    # Um lote de acordos: uma leitura de títulos e uma de eventos; devolve os acordos cuja situação mudou. As mudanças simples (em dia, em atraso) vão em SQL de conjunto.
    def refresh_many(agreements, today: Date.current, loaded: nil)
      return [] if agreements.empty?

      titles, ledgers = loaded || LedgerLoader.new(agreements.first.tenant, today: today).for_agreements(agreements)
      verdicts = agreements.filter_map { |agreement| (verdict = verdict(agreement, titles.fetch(agreement.id, []), ledgers, today)) && [ agreement, verdict ] }
      simple, complex = verdicts.partition { |_, verdict| verdict.rests.nil? }
      complex.each { |agreement, verdict| apply!(agreement, verdict, today: today) }
      bulk_move(simple)
      verdicts.map(&:first)
    end

    # A situação que o acordo deve ter, ou nil quando não muda.
    def verdict(agreement, all_titles, ledgers, today)
      return nil unless %w[active_on_time active_late broken].include?(agreement.state)
      return nil if agreement.reversing?

      titles = all_titles.reject { |bill| %w[canceled scheduled].include?(bill.status) }
      return nil if titles.empty? # quebrado antes da efetivação: todos os títulos foram cancelados

      # R250: o título renegociado em acordo novo não é dívida deste acordo; sem título próprio em aberto e com algum renegociado, o acordo fica renegociado (em vez de quitado).
      renegotiated = titles.any?(&:renegotiated?)
      done = renegotiated ? "renegotiated" : "settled"
      titles = titles.reject(&:renegotiated?)
      open = titles.reject(&:paid?)
      return Verdict.new(done, done, nil) if open.empty?

      rests = open.to_h { |bill| [ bill, ledgers.fetch(bill.id).due(today) ] }
      minimum = agreement.minimum_cents
      if minimum.positive? && rests.keys.all? { |bill| ledgers.fetch(bill.id).paid_any? && !bill.composition["no_minimum"] } && rests.values.sum(&:total) <= minimum
        return Verdict.new(done, done, rests)
      end
      return nil if agreement.state_broken?

      late = open.any? { |bill| today > agreement.deadline_for(bill, agreement.tolerance_days) }
      state = late ? "active_late" : "active_on_time"
      state == agreement.state ? nil : Verdict.new(state, late ? "late" : "on_time", nil)
    end

    def apply!(agreement, verdict, today:, payment_id: nil)
      abate_minimum!(agreement, verdict.rests, today, payment_id) if verdict.rests
      move(agreement, verdict.state, verdict.event)
    end

    # O resto de cada título aberto vira abatimento por mínimo e o título fica pago (R229). O abatimento cita o último pagamento do acordo.
    def abate_minimum!(agreement, rests, today, payment_id)
      payment_id ||= Payment.where(bill_id: Bill.where(agreement_id: agreement.id).select(:id)).or(Payment.where(agreement_id: agreement.id)).order(:paid_on, :id).last&.id
      rests.each do |bill, due|
        parts = due.parts.except("late")
        parts.each { |component, cents| Abatement.create!(tenant_id: agreement.tenant_id, payment_id: payment_id, bill: bill, kind: "minimum", component: component, amount_cents: cents) } if payment_id
        bill.update!(paid_cents: [ bill.paid_cents + parts.values.sum, bill.amount_cents ].min, status: "paid", paid_on: today)
      end
    end

    def move(agreement, state, event)
      return agreement if agreement.state == state

      before = agreement.state
      agreement.update!(state: state, closed_at: (Time.current if %w[settled renegotiated].include?(state)))
      AgreementEvent.log!(agreement, event, data: { "from" => before })
      Change.record!(agreement, "state_changed", field: "state", before: before, after: state)
      agreement
    end

    # Em dia e em atraso em lote: a mudança, o evento e o registro (decisão 0021: Active Record, uma transação por grupo, a auditoria única e o aviso só ao fim).
    def bulk_move(pairs)
      pairs.group_by { |_, verdict| [ verdict.state, verdict.event ] }.each do |(state, event), group|
        Broadcast.quiet do
          ApplicationRecord.transaction do
            changes = group.map do |agreement, _|
              before = agreement.state
              agreement.update!(state: state, closed_at: nil)
              AgreementEvent.log!(agreement, event, data: { "from" => before })
              [ agreement, "state_changed", { field: "state", before: before, after: state } ]
            end
            Change.record_many!(changes, tenant_id: group.first.first.tenant_id)
          end
        end
      end
    end
  end
end
