module Agreements
  # O crédito do contrato na tarefa diária (11, R232b, DA23, U2, N17). Quatro comportamentos, todos só para acordo em andamento:
  # - **suspende a quebra** (padrão de "Crédito e quebra"): enquanto o crédito disponível do contrato cobre a amortização e os juros do parcelamento em atraso, o acordo não quebra
  #   (`Breaker`), os encargos de atraso ficam congelados (intervalo "credit" no acordo, N17) e a ficha avisa para usar o crédito; quando deixa de cobrir, os dias de quebra contam
  #   desse dia e os encargos do período congelado não voltam;
  # - **aplica antes de quebrar**: a tarefa usa o crédito nos títulos vencidos (de acordo e de estorno), do mais antigo para o mais novo, antes de avaliar a quebra;
  # - **aplica depois da quebra**: o acordo quebra, e o crédito abate os títulos em cobrança do acordo quebrado e os de estorno vencidos;
  # - **U2** ("crédito paga a entrada", padrão): na efetivação pelo aceite, a entrada vencida além da tolerância recebe antes o crédito disponível, mesmo que só cubra parte, e só
  #   quebra se o resto passar do mínimo; vale também com "uso do crédito: só registrar" (V2).
  # O pagamento feito com crédito pela tarefa tem a data mais tardia entre o vencimento do título e o dia em que o crédito ficou disponível para o contrato (W4, Z9), então o crédito
  # que já existia no vencimento deixa o título pago em dia, sem encargos. O uso consome primeiro o crédito disponível há mais tempo.
  class CreditCover
    def initialize(tenant) = @tenant = tenant

    # Roda antes da avaliação da quebra. Devolve os acordos tocados.
    def before_review(today)
      touched = []
      setting = @tenant.setting
      @funded = nil
      # Sem contrato com crédito disponível e sem intervalo congelado aberto, não há o que fazer (o caso comum): nenhuma leitura de títulos.
      return [] if funded_contracts.empty? && !open_freezes?

      entry_by_credit(today).each { |agreement| touched << agreement }
      return touched.uniq unless Policies.value(setting, "credit_use") == "in_agreement"

      case Policies.value(setting, "credit_and_break")
      when "before_break" then touched.concat(apply_to_overdue(today, only_running: true))
      when "suspends" then touched.concat(sync_freeze(today))
      end
      touched.concat(apply_to_reversal_titles(today)) unless Policies.value(setting, "credit_and_break") == "after_break"
      touched.uniq
    end

    # Roda depois da quebra: "aplica depois da quebra" abate os títulos em cobrança dos acordos quebrados e os de estorno vencidos.
    def after_break(today)
      return [] unless Policies.value(@tenant.setting, "credit_use") == "in_agreement" && Policies.value(@tenant.setting, "credit_and_break") == "after_break"

      apply_to_overdue(today, only_running: false, states: %w[broken]) + apply_to_reversal_titles(today)
    end

    # --- U2 ---
    def entry_by_credit(today)
      return [] if Policies.value(@tenant.setting, "credit_and_late_down_payment") != "credit_pays"

      Agreement.where(tenant_id: @tenant.id, state: %w[active_on_time active_late], effectuated_by: "acceptance").where(id: with_funded_titles).filter_map do |agreement|
        next if agreement.reversing?

        entry = agreement.entry_title
        next unless entry&.active? && today > agreement.deadline_for(entry, agreement.tolerance_days)

        paid = apply!(entry, today, agreement)
        agreement if paid.positive?
      end
    end

    # --- N17 ---
    # Abre ou fecha o intervalo congelado de cada acordo ativo conforme o crédito do contrato cobre, ou não, o atraso.
    def sync_freeze(today)
      changed = []
      Agreement.where(tenant_id: @tenant.id, state: %w[active_on_time active_late]).where(id: with_funded_titles).or(Agreement.where(id: open_freeze_ids)).find_each do |agreement|
        next if agreement.reversing?

        covered = covers?(agreement, today)
        open = agreement.frozen_spans.find { |span| span["kind"] == "credit" && span["to"].nil? }
        # `update_columns`: o intervalo congelado é só um dado de prazo (sem validação nem o aviso do WebSocket por acordo; a tarefa avisa uma vez no fim). Medido: com 2.500 acordos, o
        # `update!` com o aviso dobrava o tempo da tarefa.
        if covered && !open
          agreement.update_columns(terms: agreement.terms.merge("frozen" => agreement.frozen_spans + [ { "kind" => "credit", "from" => today.iso8601, "to" => nil } ]), updated_at: Time.current)
          changed << agreement
        elsif !covered && open
          spans = agreement.frozen_spans.map { |span| span.equal?(open) || span == open ? span.merge("to" => today.iso8601) : span }
          agreement.update_columns(terms: agreement.terms.merge("frozen" => spans), updated_at: Time.current)
          changed << agreement
        end
      end
      changed
    end

    # O crédito disponível dos contratos dos títulos em atraso cobre a amortização e os juros do parcelamento em atraso? (R232b)
    def covers?(agreement, today)
      overdue = agreement.titles.where(status: "active").select { |bill| today > agreement.deadline_for(bill, agreement.tolerance_days) }
      return false if overdue.empty?

      ledgers = LedgerLoader.new(@tenant, today: today).call(overdue)
      due = overdue.sum { |bill| ledgers.fetch(bill.id).due(today).parts.except("late").values.sum }
      Credit.available.where(contract_id: overdue.map(&:contract_id).uniq).sum(:amount_cents) >= due
    end

    private
      # Os contratos do credor com crédito disponível (uma consulta, o índice de `credits (contract_id, bucket)`): só neles a tarefa tem o que usar.
      def funded_contracts
        @funded ||= Credit.where(tenant_id: @tenant.id, bucket: "available").group(:contract_id).having("sum(amount_cents) > 0").pluck(:contract_id)
      end

      # Os acordos que têm título em contrato com crédito (índice parcial de `bills (agreement_id)`).
      def with_funded_titles = Bill.where(tenant_id: @tenant.id, status: "active", contract_id: funded_contracts).where.not(agreement_id: nil).select(:agreement_id)

      def open_freeze_ids = Agreement.where(tenant_id: @tenant.id, state: %w[active_on_time active_late]).where("terms @> ?::jsonb", '{"frozen":[{"kind":"credit","to":null}]}').select(:id)

      def open_freezes? = open_freeze_ids.exists?

      # DA23, "aplica antes de quebrar" e "aplica depois da quebra": os títulos vencidos, do mais antigo para o mais novo.
      def apply_to_overdue(today, only_running:, states: %w[active_on_time active_late])
        touched = []
        Agreement.where(tenant_id: @tenant.id, state: states).where(id: with_funded_titles).find_each do |agreement|
          next if agreement.reversing?

          agreement.titles.where(status: "active").where(due_date: ...today).each do |bill|
            touched << agreement if apply!(bill, today, agreement).positive?
          end
        end
        touched
      end

      # AG7: o título de estorno vencido também recebe o crédito nas opções automáticas.
      def apply_to_reversal_titles(today)
        Bill.where(tenant_id: @tenant.id, kind: "reversal", status: "active", contract_id: funded_contracts).where(due_date: ...today).includes(:origin_agreement).filter_map do |bill|
          bill.origin_agreement if apply!(bill, today, bill.origin_agreement).positive?
        end
      end

      # Paga o título com o crédito disponível do contrato, com a data do uso (Z9). Devolve os centavos usados.
      def apply!(bill, today, agreement)
        available = CreditBook.balance(bill.contract_id)
        return 0 unless available.positive?

        date = [ bill.due_date, CreditBook.availability_date(bill.contract_id, available) ].max
        date = today if date > today
        ledger = LedgerLoader.new(@tenant, today: today).one(bill)
        owed = ledger.due(date).total
        cents = [ available, owed ].min
        return 0 unless cents.positive?

        # O valor é no máximo o devido na data, então o aplicado é o próprio valor (sem reler o pagamento depois).
        payment = Payment.create!(tenant_id: bill.tenant_id, channel: (@channel ||= CreditUse.channel_for(@tenant)), identifier: "CRED-AUTO-#{SecureRandom.hex(5)}", document: bill.customer.document,
                                  bill_number: bill.number, bill: bill, paid_on: date, amount_cents: cents, applied_cents: cents, payment_method: "other", status: "applied")
        outcome = TitleSettler.pay!(payment, bill, cents, date, tolerance: agreement&.tolerance_spec, ledger: ledger)
        payment.update_columns(applied_cents: outcome.applied) if outcome.applied != cents
        CreditBook.take!(bill.contract_id, outcome.applied, kind: "used", reason: "used_on_title", bill_id: bill.id, note: bill.number, tenant_id: @tenant.id)
        outcome.applied
      end
  end
end
