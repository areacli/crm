module Agreements
  # O pagamento de acordo dentro da confirmação (e da conferência) de pagamentos (11, R225 a R232a): a linha traz o número de um título de acordo (`ACD-000001-02`,
  # `-00` é a entrada, `-Q` o título da quebra) ou o do acordo sem sufixo (`ACD-000001`). Os dados dos acordos tocados pelo lote são lidos de uma vez, e o que o arquivo aloca
  # fica na memória até o fim do lote, como no `Promises::PaymentFlow`: a conferência vê o mesmo que a confirmação vai gravar. A situação do acordo (efetivação,
  # cancelamento, ativo em atraso, quitado) é gravada no fim (`finalize`), depois de todos os lotes.
  #
  # Casos (linhas que não batem, R231): antes da efetivação todo pagamento dirigido ao acordo vai primeiro à entrada (AB2, AC11); título de acordo pago, ou de acordo
  # encerrado, é excedente (DA9); título de acordo cancelado, ou de acordo que quebrou antes da efetivação, vale como pagamento comum dos originais, do mais antigo para o
  # mais novo; o número do acordo sem sufixo depois da efetivação usa o cálculo de quitação vigente (R230) e, sem ele, paga os títulos do mais antigo para o mais novo.
  class PaymentFlow
    Sql = Portfolio::Sql

    Handle = Struct.new(:agreement, :state, :titles, :originals, :ledgers, :policies, :quotes, :effectuate, :cancel_reason, :entry, :reactivation_check, :reversal_titles, keyword_init: true)
    # `target`: o título que recebe o pagamento (para o registro do pagamento); `allocations`: [[id do título, componentes]]; `abatements`: [[id do título, tipo, componentes]].
    Outcome = Struct.new(:target, :agreement_id, :applied, :credit, :reason, :allocations, :abatements, :settled, :partial, :contract_id, :quitted, :bucket, keyword_init: true) do
      def initialize(**)
        super
        self.applied ||= 0
        self.credit ||= 0
        self.reason ||= "excess"
        self.allocations ||= []
        self.abatements ||= []
        self.settled ||= 0
        self.partial ||= 0
      end
    end

    attr_reader :touched

    def initialize(tenant, setting, states, charges)
      @tenant = tenant
      @setting = setting
      @states = states
      @charges = charges
      @handles = {}
      @touched = Set.new
      @snapshot = {}
    end

    # Os acordos que as linhas tocam: o título de acordo da linha, o acordo pelo número sem sufixo e o acordo que prende o título original (pagamento direto, DA7).
    def begin_lot(rows)
      ids = rows.flat_map { |row| [ row["bill_agreement_id"], row["bill_origin_agreement_id"], row["agreement_ref_id"], row["held_agreement_id"] ] }.compact.map(&:to_i).uniq - @handles.keys
      load(ids) if ids.any?
    end

    def owns?(row) = row["bill_agreement_id"].present? || row["bill_origin_agreement_id"].present? || row["agreement_ref_id"].present?

    # Pagamento ao título de estorno pelo número (`ACD-000001-E1`, R233): paga o próprio título, fora do acordo; o excedente vira crédito do contrato dele. Não mexe no acordo.
    def settle_reversal_title(row, amount, pay_date)
      handle = @handles.fetch(row["bill_origin_agreement_id"].to_i)
      title = handle.reversal_titles.find { |item| item.id == row["bill_id"].to_i }
      outcome = Outcome.new(agreement_id: handle.agreement.id, contract_id: title.contract_id, target: title.id)
      return excess(handle, outcome, amount, "already_paid", after: title).then { outcome } unless state_of(title)[1] == "active"

      remaining = pay_title(handle, title, amount, pay_date, outcome, row["final_state"])
      outcome.credit += remaining if remaining.positive?
      outcome
    end

    # DA7 (padrão): o pagamento direto a um título original antes da efetivação vai para o título e cancela o acordo. Na alternativa, vale como pagamento do acordo.
    def counts_as_agreement?(row)
      handle = @handles[row["held_agreement_id"]&.to_i] or return false
      handle.state == "awaiting_effectuation" && policy(handle, "original_paid_before") == "counts_as_agreement"
    end

    def original_paid(row)
      handle = @handles[row["held_agreement_id"]&.to_i] or return
      return unless handle.state == "awaiting_effectuation" && policy(handle, "original_paid_before") != "counts_as_agreement"

      handle.state = "canceled"
      handle.cancel_reason = "título pago fora do acordo"
      @touched << handle.agreement.id
    end

    # Pagamento a um título de acordo (ou a um título original que a política manda tratar como pagamento do acordo): `row["bill_id"]`.
    def settle_title(row, amount, pay_date)
      bill_id = row["bill_id"].to_i
      handle = @handles.fetch(row["bill_agreement_id"].to_i)
      title = handle.titles.find { |item| item.id == bill_id }
      outcome = settle_by_state(handle, title, amount, pay_date, row)
      cancel_successor(row, handle) if outcome.applied.positive?
      outcome
    end

    # P1 (R250): o pagamento a título do anterior preso a acordo novo aguardando efetivação cancela o novo, com o motivo "acordo anterior pago ou quebrado".
    def cancel_successor(row, handle)
      held_id = row["held_agreement_id"]&.to_i
      return unless held_id && held_id != handle.agreement.id && row["held_state"] == "awaiting_effectuation"

      successor = @handles[held_id] or return
      return unless successor.state == "awaiting_effectuation"

      successor.state = "canceled"
      successor.cancel_reason = Renegotiation::REASON
      @touched << successor.agreement.id
    end

    # Pagamento com o número do acordo sem sufixo (R230).
    def settle_number(row, amount, pay_date)
      handle = @handles.fetch(row["agreement_ref_id"].to_i)
      settle_by_state(handle, nil, amount, pay_date, row)
    end

    # DA8, alternativa "abate o título de acordo mais antigo": o pagamento a um título original já renegociado abate o título de acordo mais antigo em aberto do acordo que o
    # renegociou; o que passar dele segue a DA9.
    def rebate_oldest?(row, status)
      return false unless status == "renegotiated" && row["held_agreement_id"] && %w[active_on_time active_late broken].include?(row["held_state"])

      Policies.value(@tenant.setting, "renegotiated_payment") == "rebate_oldest"
    end

    def settle_rebate_oldest(row, amount, pay_date)
      handle = @handles.fetch(row["held_agreement_id"].to_i)
      @touched << handle.agreement.id
      outcome = Outcome.new(agreement_id: handle.agreement.id, contract_id: handle.originals.first.contract_id)
      oldest = handle.titles.select { |item| state_of(item)[1] == "active" }.min_by { |item| [ item.due_date, item.id ] }
      return excess(handle, outcome, amount, "renegotiated", after: nil).then { outcome } unless oldest

      outcome.target = oldest.id
      remaining = pay_title(handle, oldest, amount, pay_date, outcome, row["final_state"])
      excess_chain(handle, oldest, remaining, pay_date, outcome)
      outcome
    end

    # Pagamento direto que "vale como pagamento do acordo" (DA7, alternativa): primeiro a entrada, depois os títulos de acordo.
    def settle_as_agreement(row, amount, pay_date)
      handle = @handles.fetch(row["held_agreement_id"].to_i)
      settle_by_state(handle, nil, amount, pay_date, row)
    end

    # Grava as situações dos acordos tocados (só na confirmação): cancelamento automático, efetivação, ativo em dia ou em atraso, quitado. Cancelar e efetivar mexem em títulos e
    # vão um a um; a reavaliação do resto é um lote só (uma leitura de títulos e de eventos, e SQL de conjunto para o que muda).
    def finalize(today: Date.current)
      plain = []
      customers = []
      @touched.each do |id|
        handle = @handles.fetch(id)
        agreement = handle.agreement
        customers << agreement.customer_id
        if handle.cancel_reason
          Release.new.call(agreement, to: "canceled", reason: handle.cancel_reason, event: "canceled", on: today)
        elsif handle.effectuate
          Effectuation.call(agreement, by: "payment", at: handle.effectuate)
          Standing.refresh!(agreement, today: today)
        else
          Reactivation.after_payment!(agreement) if handle.reactivation_check
          plain << agreement
        end
      end
      Standing.refresh_many(plain, today: today)
      AgreementSettlement.where(agreement_id: @touched.to_a, expired_at: nil).update_all(expired_at: Time.current)
      Broadcast.changed(@tenant, customers.first(200))
    end

    private
      # --- Escolhe o caminho pelo estado do acordo e do título ---
      def settle_by_state(handle, title, amount, pay_date, row)
        outcome = Outcome.new(agreement_id: handle.agreement.id, contract_id: (handle.entry || handle.originals.first)&.contract_id || handle.originals.first.contract_id)
        @touched << handle.agreement.id
        final_state = row["final_state"]
        # R239: com o acordo em reversão, o pagamento que chega a título dele vira crédito do contrato aguardando alocação (o dinheiro entrou; o gestor decide).
        if handle.agreement.reversing?
          outcome.credit = amount
          outcome.reason = "during_reversal"
          outcome.bucket = "awaiting"
          return outcome
        end
        reactivate_before(handle, pay_date) if handle.state == "broken" && handle.agreement.break_kind == "before_effectuation"
        reactivate_single_title(handle, title, pay_date) if handle.state == "broken" && handle.agreement.break_kind == "after_effectuation"
        case handle.state
        when "awaiting_effectuation"
          before_effectuation(handle, title, amount, pay_date, outcome, final_state)
        when "active_on_time", "active_late", "settled"
          after_effectuation(handle, title, amount, pay_date, outcome, final_state)
        when "broken"
          # Quebrado depois da efetivação: o pagamento é do título correspondente, e o pagamento no prazo pode reativar o acordo (R231, R236a).
          after_effectuation(handle, title, amount, pay_date, outcome, final_state)
          handle.reactivation_check = true
        else
          # Acordo cancelado ou quebrado antes da efetivação: pagamento comum dos títulos originais, do mais antigo para o mais novo (R231).
          common_chain(handle, amount, pay_date, outcome)
        end
        outcome
      end

      # Antes da efetivação todo pagamento dirigido ao acordo vai primeiro à entrada, e o que passar dela segue a DA9 (AB2, AC11).
      def before_effectuation(handle, _title, amount, pay_date, outcome, final_state)
        entry = handle.entry
        outcome.target = entry.id
        # N6: a entrada paga depois do vencimento só gera crédito, se a política manda; o crédito é do contrato da entrada.
        if pay_date > entry.due_date && policy(handle, "late_down_payment") == "credit_only"
          outcome.credit = amount
          outcome.reason = "excess"
          return
        end
        paid_state = state_of(entry)
        return excess(handle, outcome, amount, "already_paid", after: entry) if paid_state[1] == "paid"

        remaining = pay_title(handle, entry, amount, pay_date, outcome, final_state)
        effectuate!(handle, pay_date) if entry_covered?(handle, entry, pay_date)
        excess_chain(handle, entry, remaining, pay_date, outcome)
      end

      def after_effectuation(handle, title, amount, pay_date, outcome, final_state)
        if title.nil?
          number_payment(handle, amount, pay_date, outcome, final_state)
        else
          outcome.target = title.id
          status = state_of(title)[1]
          return excess(handle, outcome, amount, "already_paid", after: title) if status == "paid"
          # R250, DA8: o título de acordo já renegociado em acordo novo recebe o pagamento como crédito do contrato dele.
          return excess(handle, outcome, amount, "renegotiated", after: title) if status == "renegotiated"
          # O título da quebra desfeito pela reativação: o pagamento vai aos títulos de acordo trazidos de volta, do mais antigo para o mais novo (R236a).
          return number_payment(handle, amount, pay_date, outcome, final_state) if status == "canceled" && title.kind_break? && handle.state != "broken"
          return common_chain(handle, amount, pay_date, outcome) if status == "canceled"

          remaining = pay_title(handle, title, amount, pay_date, outcome, final_state)
          excess_chain(handle, title, remaining, pay_date, outcome)
        end
      end

      # O número do acordo sem sufixo depois da efetivação (R230): quitação pelo cálculo vigente, ou os títulos do mais antigo para o mais novo.
      def number_payment(handle, amount, pay_date, outcome, final_state)
        open = handle.titles.select { |item| state_of(item)[1] == "active" }
        extra = handle.reversal_titles.select { |item| state_of(item)[1] == "active" }
        return excess(handle, outcome, amount, "already_paid", after: nil) if open.empty? && extra.empty?

        quote = handle.quotes.find { |item| item.on_date >= pay_date }
        if quote && open.any? && settle_with_quote(handle, quote, open, amount, pay_date, outcome)
          return
        end
        remaining = amount
        # R231, AJ4: primeiro os títulos do acordo (os em aberto de acordo encerrado também), depois os títulos de estorno numerados por ele, do mais antigo para o mais novo.
        (open + extra).each do |item|
          break if remaining <= 0

          remaining = pay_title(handle, item, remaining, pay_date, outcome, final_state)
        end
        outcome.credit += remaining if remaining.positive?
      end

      # R230: o valor calculado (ou o saldo da data do pagamento, S5) quita todos os títulos, dispensando os juros futuros; abaixo dele o pagamento é alocado nos títulos.
      def settle_with_quote(handle, quote, open, amount, pay_date, outcome)
        by_payment_date = policy(handle, "early_settlement") == "payment_date_value" && pay_date < quote.on_date
        parts_by_bill = open.to_h do |item|
          parts = by_payment_date ? ledger_of(handle, item).balance_parts(pay_date).first : quote.parts_by_bill.fetch(item.id, {}).transform_keys(&:to_s)
          [ item.id, parts ]
        end
        total = parts_by_bill.values.sum { |items| items.values.sum }
        return false if amount < total - Policies.tolerance_of(handle.policies["tolerance_agreement"], total)

        left = [ amount, total ].min
        open.each do |item|
          parts = parts_by_bill.fetch(item.id)
          covered = TitlePayment.distribute(parts, left)
          left -= covered.values.sum
          shortfall = parts.to_h { |component, cents| [ component, cents - covered.fetch(component, 0) ] }.select { |_, cents| cents.positive? }
          ledger = ledger_of(handle, item)
          ledger.add_event(pay_date, covered, cash: true) if covered.any?
          outcome.allocations << [ item.id, covered ] if covered.any?
          if shortfall.any?
            outcome.abatements << [ item.id, "tolerance", shortfall ]
            ledger.add_event(pay_date, shortfall, cash: false)
          end
          # Os juros do parcelamento que ainda não correram são dispensados (CDC, art. 52, § 2º).
          future = ledger.face_remaining.select { |_, cents| cents.positive? }
          if future.any?
            outcome.abatements << [ item.id, "early", future ]
            ledger.add_event(pay_date, future, cash: false)
          end
          outcome.applied += covered.values.sum
          mark_paid(item, ledger, pay_date, covered, shortfall.merge(future) { |_, a, b| a + b })
          outcome.settled += 1
        end
        outcome.credit += amount - total if amount > total
        outcome.contract_id = open.first.contract_id
        outcome.quitted = true
        true
      end

      # R236a: o pagamento da entrada no prazo, importado depois da quebra antes da efetivação, reativa o acordo; o dado do acordo é relido do banco.
      def reactivate_before(handle, pay_date)
        return unless Reactivation.before_effectuation?(handle.agreement, pay_date)

        Reactivation.restore_before_effectuation!(handle.agreement)
        reload(handle.agreement.id)
      end

      # R236a, título único: o pagamento ao título da quebra no prazo desfaz o título da quebra e traz de volta os títulos de acordo.
      def reactivate_single_title(handle, title, pay_date)
        return unless title && title.kind_break? && Reactivation.single_title?(handle.agreement, pay_date)

        Reactivation.restore_single_title!(handle.agreement)
        reload(handle.agreement.id)
      end

      def reload(id)
        @handles.delete(id)
        load([ id ])
      end

      # --- Alocação num título ---
      def pay_title(handle, title, amount, pay_date, outcome, final_state)
        ledger = ledger_of(handle, title)
        result = TitlePayment.call(ledger, date: pay_date, amount: amount, tolerance: handle.policies["tolerance_agreement"], final_state: final_state)
        if result.parts.empty? && result.abatements.empty?
          return amount
        end

        ledger.add_event(pay_date, result.parts, cash: true) if result.parts.any?
        result.abatements.each { |kind, parts| ledger.add_event(pay_date, parts, cash: false) }
        outcome.allocations << [ title.id, result.parts ] if result.parts.any?
        result.abatements.each { |kind, parts| outcome.abatements << [ title.id, kind, parts ] }
        outcome.applied += result.applied
        if result.settled then outcome.settled += 1 else outcome.partial += 1 end
        mark_paid(title, ledger, pay_date, result.parts, result.abatements.to_h.values.reduce({}) { |sum, parts| sum.merge(parts) { |_, a, b| a + b } })
        result.excess
      end

      # O que cobriu a face entra no pago do título, e o título que não deve mais nada fica pago.
      def mark_paid(title, ledger, pay_date, parts, abated)
        paid, status, paid_on = state_of(title)
        covered = parts.sum { |component, cents| component == "late" ? 0 : cents } + abated.sum { |component, cents| component == "late" ? 0 : cents }
        paid += covered
        done = ledger.face_remaining.values.sum.zero?
        @states.put(title.id, paid: paid, status: done ? "paid" : status, paid_on: done ? pay_date : paid_on, keep: true)
      end

      # O excedente do pagamento (DA9): crédito do contrato do título (padrão) ou abate os títulos de acordo seguintes.
      def excess_chain(handle, title, remaining, pay_date, outcome)
        return if remaining <= 0

        if policy(handle, "overpayment") == "rebate_next"
          later = handle.titles.select { |item| item.due_date >= title.due_date && item.id != title.id && %w[active scheduled].include?(state_of(item)[1]) }.sort_by { |item| [ item.due_date, item.id ] }
          later.each do |item|
            break if remaining <= 0

            remaining = pay_title(handle, item, remaining, pay_date, outcome, nil)
          end
        end
        outcome.credit += remaining if remaining.positive?
        outcome.contract_id = title.contract_id
      end

      def excess(handle, outcome, amount, reason, after:)
        outcome.credit += amount
        outcome.reason = reason
        outcome.contract_id = (after || handle.entry || handle.originals.first).contract_id
      end

      # Pagamento comum dos títulos originais do acordo, do mais antigo para o mais novo, encargos antes do principal (R226): acordo cancelado ou quebrado antes da efetivação.
      def common_chain(handle, amount, pay_date, outcome)
        remaining = amount
        handle.originals.each do |original|
          break if remaining <= 0

          paid, status, paid_on = state_of(original)
          next unless status == "active"

          due = @charges&.due(original.id, pay_date, [ original.amount_cents - paid, 0 ].max)
          result = Payments::Allocation.call(@setting, bill_amount: original.amount_cents, status: "active", paid: paid, amount: remaining, due: due, tolerance: false)
          @charges&.record(original.id, pay_date, result.components)
          @states.put(original.id, paid: paid + result.principal, status: result.settled ? "paid" : status, paid_on: result.settled ? pay_date : paid_on, keep: true)
          outcome.allocations << [ original.id, result.components ] if result.components.any?
          outcome.applied += result.applied
          if result.settled then outcome.settled += 1 else outcome.partial += 1 if result.applied.positive? end
          remaining = result.credit
        end
        outcome.credit += remaining if remaining.positive?
        outcome.reason = "excess"
        outcome.contract_id = handle.originals.first.contract_id
      end

      # --- Efetivação (R225, R229) ---
      def entry_covered?(handle, entry, pay_date)
        rest = ledger_of(handle, entry).due(pay_date).total
        minimum = handle.agreement.minimum_cents
        rest.zero? || (minimum.positive? && rest <= minimum)
      end

      def effectuate!(handle, pay_date)
        return unless handle.state == "awaiting_effectuation"

        handle.state = "active_on_time"
        handle.effectuate = pay_date.in_time_zone
        handle.originals.each do |original|
          paid, status, paid_on = state_of(original)
          @states.put(original.id, paid: paid, status: "renegotiated", paid_on: paid_on, keep: true) if status == "active"
        end
        handle.titles.each do |title|
          paid, status, paid_on = state_of(title)
          @states.put(title.id, paid: paid, status: "active", paid_on: paid_on, keep: true) if status == "scheduled"
        end
      end

      # --- Dados ---
      # A política do dia que o acordo congelou, ou, se não congela, a do credor hoje (R210).
      def policy(handle, key) = handle.policies.key?(key) ? handle.policies[key] : Policies.value(@tenant.setting, key)

      def state_of(bill) = @states.get(bill.id) || @snapshot.fetch(bill.id) { [ bill.paid_cents, bill.status, bill.paid_on ] }

      def ledger_of(handle, title) = handle.ledgers.fetch(title.id)

      def load(ids)
        agreements = Agreement.select(Agreement.column_names - %w[term_snapshot]).where(id: ids, tenant_id: @tenant.id).includes(:agreement_bills).to_a
        return if agreements.empty?

        titles_by = Bill.where(agreement_id: agreements.map(&:id)).order(:due_date, :id).group_by(&:agreement_id)
        reversal_by = Bill.where(origin_agreement_id: agreements.map(&:id)).order(:due_date, :id).group_by(&:origin_agreement_id)
        original_ids = agreements.flat_map { |agreement| agreement.agreement_bills.map(&:bill_id) }
        originals_by_id = Bill.where(id: original_ids).index_by(&:id)
        ledgers = LedgerLoader.new(@tenant, today: Date.current).call(titles_by.values.flatten + reversal_by.values.flatten, agreements: agreements)
        quotes = AgreementSettlement.valid_on(Date.new(2000, 1, 1)).where(agreement_id: agreements.map(&:id)).group_by(&:agreement_id)
        @charges&.preload(original_ids)
        agreements.each do |agreement|
          titles = titles_by.fetch(agreement.id, [])
          originals = agreement.agreement_bills.map { |item| originals_by_id[item.bill_id] }.compact.sort_by { |bill| [ bill.due_date, bill.id ] }
          reversal = reversal_by.fetch(agreement.id, [])
          (titles + originals + reversal).each { |bill| @snapshot[bill.id] = [ bill.paid_cents, bill.status, bill.paid_on ] }
          @handles[agreement.id] = Handle.new(agreement: agreement, state: agreement.state, titles: titles, originals: originals, reversal_titles: reversal, ledgers: ledgers.slice(*(titles + reversal).map(&:id)),
                                              policies: agreement.terms["policies"].to_h.merge("tolerance_agreement" => agreement.tolerance_spec), quotes: quotes.fetch(agreement.id, []),
                                              entry: titles.find { |title| title.number == Titles.number_of(agreement, 0) })
        end
      end
  end
end
