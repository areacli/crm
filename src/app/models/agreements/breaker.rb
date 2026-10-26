module Agreements
  # A quebra do acordo (11, R234 a R238): quem não paga a entrada até o vencimento mais a tolerância, ou a parcela até o vencimento mais os dias de quebra, quebra o acordo. O
  # fim de prazo em dia não útil passa ao dia útil seguinte, e o acordo quebra no dia seguinte ao fim do prazo. O resto abaixo do mínimo não quebra (R229), mas só vale para o
  # título que recebeu algum pagamento vigente; o que não recebeu nada conta como atraso cheio.
  #
  # Antes da efetivação a quebra libera os originais (`Release`, R235). Depois dela, os títulos seguem em cobrança na forma congelada no acordo (R236): "parcelas seguem" (cada
  # título com o vencimento dele e a mora desde ele) ou "título único" (nasce `ACD-000001-Q`, com o devido no dia da quebra, e os títulos não pagos são cancelados). A quebra
  # depois da efetivação é a marca histórica "já quebrou acordo" (R248).
  module Breaker
    module_function

    # O que quebra o acordo em `today`: nil ou o texto curto do motivo ("entrada" ou "parcela").
    # `credits`: o crédito disponível por contrato, lido uma vez para o lote (a tarefa diária); sem ele, cada acordo lê o do contrato dele.
    def cause(agreement, today, titles: nil, ledgers: nil, credits: nil)
      return nil if agreement.reversing? # R239: em reversão a tarefa diária não quebra o acordo

      case agreement.state
      when "awaiting_effectuation" then entry_cause(agreement, today, titles, ledgers)
      when "active_on_time", "active_late" then installments_cause(agreement, today, titles, ledgers, credits)
      end
    end

    # Quebra manual (R238, DA12), com motivo, por quem tem "administrar acordos": mesmos efeitos da quebra automática. Só para acordo em atraso há mais que a tolerância, ou por fraude.
    # Recuperação judicial e óbito do devedor ficam fora (N19).
    def manual!(agreement, actor, reason:, fraud: false, today: Date.current)
      reason = reason.to_s.strip
      raise Refused, I18n.t("agreements.refused.break_reason_required") if reason.empty?
      raise Refused, I18n.t("agreements.refused.reason_too_long", max: Canceller::MAX_REASON) if reason.length > Canceller::MAX_REASON

      ApplicationRecord.transaction do
        agreement.lock!
        raise Refused, I18n.t("agreements.refused.not_breakable") unless %w[awaiting_effectuation active_on_time active_late].include?(agreement.state)
        raise Refused, I18n.t("agreements.refused.not_late") unless fraud || late_beyond_tolerance?(agreement, today)

        break!(agreement, cause: "manual", today: today, actor: actor, reason: reason, manual: true)
      end
    end

    def late_beyond_tolerance?(agreement, today)
      titles = agreement.state_awaiting_effectuation? ? [ agreement.entry_title ].compact : agreement.titles.where(status: "active")
      titles.any? { |bill| today > agreement.deadline_for(bill, agreement.tolerance_days) }
    end

    # Vários acordos de uma vez, o que a tarefa diária faz (R234): na forma "parcelas seguem" a quebra depois da efetivação é SQL de conjunto (a mudança, o evento, o registro e a marca
    # "já quebrou acordo"); a forma "título único" e a quebra antes da efetivação criam ou desfazem títulos, e vão um a um.
    def break_many!(pairs, today:)
      bulk, single = pairs.partition { |agreement, _| !agreement.state_awaiting_effectuation? && agreement.frozen_policy("break_form") == "installments_follow" }
      single.each { |agreement, cause| break!(agreement, cause: cause, today: today) }
      bulk.group_by { |_, cause| cause }.each do |cause, group|
        ids = group.map { |agreement, _| agreement.id }
        reason = I18n.t("agreements.break_reasons.#{cause}")
        now = Time.current
        # Active Record (decisão 0021): a mudança, o evento e o registro de cada acordo numa transação por grupo, com o aviso das telas só ao fim.
        Broadcast.quiet do
          ApplicationRecord.transaction do
            changes = group.map do |agreement, _|
              before = agreement.state
              agreement.update!(state: "broken", broken_at: now, break_kind: "after_effectuation", break_form: "installments_follow", broken_after_effectuation: true, reason: reason)
              AgreementEvent.log!(agreement, "broken", data: { form: "installments_follow", reason: reason })
              [ agreement, "state_changed", { field: "state", before: before, after: "broken", note: reason } ]
            end
            Change.record_many!(changes, tenant_id: group.first.first.tenant_id)
            Contract.where(broke_agreement: false, id: AgreementBill.where(agreement_id: ids).select(:contract_id)).find_each { |contract| contract.update!(broke_agreement: true) }
          end
        end
        # P1: só há acordo novo a cancelar se o credor tem algum aguardando efetivação (consulta pelo índice de estado); o caso comum não paga nada.
        group.each { |agreement, _| Renegotiation.cancel_successors(agreement.reload, on: today) } if Agreement.where(tenant_id: group.first.first.tenant_id, state: "awaiting_effectuation").exists?
        Broadcast.changed(group.first.first.tenant, group.first(200).map { |agreement, _| agreement.customer_id })
      end
    end

    def break!(agreement, cause:, today: Date.current, actor: nil, reason: nil, manual: false)
      kind = manual ? "manual" : nil
      if agreement.state_awaiting_effectuation?
        Release.new(actor).call(agreement, to: "broken", reason: reason || I18n.t("agreements.break_reasons.#{cause}"), event: "broken", on: today, break_kind: kind || "before_effectuation")
      else
        break_after_effectuation!(agreement, cause: cause, today: today, actor: actor, reason: reason, manual: manual)
      end
      BrokeFlag.sync!(agreement)
      Renegotiation.cancel_successors(agreement, actor: actor, on: today)
      Broadcast.changed(agreement.tenant, [ agreement.customer_id ])
      agreement
    end

    # --- Os prazos ---

    # Entrada não paga até o vencimento mais a tolerância, acima do mínimo (R234). A entrada sem nenhum pagamento vigente quebra sempre; com pagamento parcial, só se o resto passa do mínimo.
    def entry_cause(agreement, today, titles = nil, ledgers = nil)
      entry = titles ? titles.find { |bill| bill.number == Titles.number_of(agreement, 0) } : agreement.entry_title
      return unless entry && today > agreement.deadline_for(entry, agreement.tolerance_days)

      ledger = ledgers ? ledgers.fetch(entry.id) : LedgerLoader.new(agreement.tenant, today: today).one(entry)
      rest = ledger.due(today).total
      return if rest.zero?

      "entry" if !ledger.paid_any? || rest > agreement.minimum_cents
    end

    # Algum título de acordo vencido há mais dos dias de quebra, acima do mínimo (R234, R229). Na efetivação pelo aceite, a entrada só tem a tolerância (M2).
    def installments_cause(agreement, today, titles = nil, ledgers = nil, credits = nil)
      titles = titles ? titles.select(&:active?) : agreement.titles.where(status: "active").to_a
      return if titles.empty?

      ledgers ||= LedgerLoader.new(agreement.tenant, today: today).call(titles, agreements: [ agreement ])
      by_acceptance = agreement.effectuated_by != "payment"
      limit = ->(bill) { by_acceptance && bill.number == Titles.number_of(agreement, 0) ? agreement.tolerance_days : agreement.break_days }
      beyond = titles.select { |bill| today > agreement.deadline_for(bill, limit.call(bill)) }
      return if beyond.empty?
      return if credit_covers?(agreement, beyond, ledgers, today, credits)
      return "installment" if beyond.any? { |bill| !ledgers.fetch(bill.id).paid_any? }

      counted = agreement.frozen_policy("minimum_sum") == "beyond_break_days" ? beyond : titles.select { |bill| today > agreement.deadline_for(bill, agreement.tolerance_days) }
      sum = counted.sum { |bill| ledgers.fetch(bill.id).due(today).total }
      "installment" if sum > agreement.minimum_cents
    end

    # R232b, DA23 (padrão "suspende a quebra"): enquanto o crédito disponível do contrato cobre a amortização e os juros do parcelamento em atraso, o acordo não quebra. As
    # alternativas "aplica antes de quebrar" e "aplica depois da quebra" e a suspensão dos encargos (N17) são da etapa 5.
    def credit_covers?(agreement, overdue, ledgers, today, credits = nil)
      setting = agreement.tenant.setting
      return false unless Policies.value(setting, "credit_and_break") == "suspends" && Policies.value(setting, "credit_use") == "in_agreement"

      contract_ids = overdue.map(&:contract_id).uniq
      available = credits ? contract_ids.sum { |id| credits.fetch(id, 0) } : Credit.available.where(contract_id: contract_ids).sum(:amount_cents)
      return false unless available.positive? # sem crédito não há o que cobrir: nem calcula o devido

      due = overdue.sum { |bill| ledgers.fetch(bill.id).due(today).parts.except("late").values.sum }
      available >= due
    end

    # --- Depois da efetivação (R236) ---

    def break_after_effectuation!(agreement, cause:, today:, actor:, reason:, manual:)
      form = agreement.frozen_policy("break_form")
      ApplicationRecord.transaction do
        agreement.lock!
        single_title!(agreement, today) if form == "single_title"
        agreement.update!(state: "broken", broken_at: Time.current, break_kind: manual ? "manual" : "after_effectuation", break_form: form, broken_after_effectuation: true,
                          reason: reason.presence || I18n.t("agreements.break_reasons.#{cause}"))
        AgreementEvent.log!(agreement, "broken", user: actor, data: { "form" => form, "reason" => agreement.reason })
        Change.record!(tenant_id: agreement.tenant_id, user: actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "active", after: "broken", note: agreement.reason)
      end
    end

    # O título da quebra (R236, DA6): as amortizações que faltam, os juros do parcelamento dos títulos com vencimento até a quebra e os encargos de atraso até essa data. Os
    # títulos de acordo não pagos são cancelados. O atraso dele, para faixa e segmento, conta do vencimento do título de acordo mais antigo não pago (DA26).
    def single_title!(agreement, today)
      open = agreement.titles.where(status: "active").where.not(kind: "break").to_a
      return if open.empty?

      ledgers = LedgerLoader.new(agreement.tenant, today: today).call(open)
      items = []
      interest = 0
      late = 0
      open.each do |bill|
        ledger = ledgers.fetch(bill.id)
        items.concat(ledger.items_remaining)
        interest += ledger.face_remaining.fetch("installment_interest", 0) if bill.due_date <= today
        late += ledger.late_owed(today)
      end
      merged = items.group_by { |item| [ item["bill_id"], item["component"] ] }.map { |(bill_id, component), group| { "bill_id" => bill_id, "component" => component, "cents" => group.sum { |item| item["cents"] } } }
      oldest = open.min_by { |bill| [ bill.due_date, bill.id ] }
      composition = { "items" => merged, "installment_interest" => interest, "period_days" => 0, "accrues_from" => today.iso8601, "fine" => false, "opening_late" => late, "number" => "Q" }
      Bill.create!(tenant_id: agreement.tenant_id, contract_id: oldest.contract_id, customer_id: agreement.customer_id, number: "#{agreement.number}-Q", due_date: oldest.due_date,
                   amount_cents: merged.sum { |item| item["cents"] } + interest, status: "active", kind: "break", agreement_id: agreement.id, product: oldest.product,
                   description: "Título da quebra do acordo #{agreement.number}", composition: composition)
      Bill.where(id: open.map(&:id)).update_all(status: "canceled", updated_at: Time.current)
    end
  end
end
