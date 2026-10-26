module Payments
  # Aplica (ou só simula) os pagamentos de uma importação sobre a carteira (R46, R46a, R50 a R53): em ordem de data de pagamento, com os pendentes cujo
  # título já existe (R52), em lotes. A conferência chama com `commit: false` e recebe os mesmos números que a confirmação vai gravar.
  #
  # Processamento em lote (decisão 0021): cada lote de `lot_size` linhas é uma transação, travada pelo mesmo bloqueio por credor dos pagamentos que chegam por
  # webhook; as linhas do lote são lidas do banco naquele instante (`PaymentStream`), a gravação é Active Record com validações e a auditoria única
  # (`Change.record_many!`), e a situação das promessas e dos acordos tocados é decidida no fim do próprio lote. O cursor e o resumo parcial ficam em
  # `imports.batch_state`, na mesma transação do lote: uma interrupção retoma do lote seguinte sem repetir nem perder nada.
  class Processor
    # Linhas por lote; atributo de classe para os testes de retomada usarem lotes pequenos.
    class_attribute :lot_size, instance_writer: false, default: 2000

    Sql = Portfolio::Sql

    # Chaves do resumo devolvido (todas inteiras): settled, partial, credits, credit_cents, pending_new, pending_applied, applied_cents,
    # pending_cents, promise_payments.
    #
    # `step`: a etapa do job (ou a do `InlineRunner`); recebe o número de lotes feitos e é o ponto seguro de interrupção.
    def run(import, commit:, step: nil)
      @import = import
      @commit = commit
      @tenant_id = import.tenant_id
      @setting = TenantSetting.find_by!(tenant_id: @tenant_id)
      @shared = Promises::PaymentFlow.shared_bill_ids(@tenant_id)
      state = commit ? (import.reload.batch_state || {}) : {}
      @summary = Hash.new(0).merge((state["effect"] || {}).symbolize_keys)
      @cursor = state["cursor"]
      @done = state.fetch("done", 0)
      @total = PaymentRow.where(import_id: import.id, ok: true).count
      @context = nil
      @progress_at = Time.current
      lots = 0
      while lot
        lots += 1
        step&.set!(lots)
      end
      @summary.to_h.symbolize_keys
    end

    private
      # Um lote: na confirmação, uma transação com o bloqueio do credor; na conferência, só a leitura e a conta. Devolve falso quando acabaram as linhas.
      def lot
        return process_lot unless @commit

        # Os avisos das telas saem uma vez por lote (o `after_commit` de cada promessa e acordo fica mudo durante o lote).
        Promises::Broadcast.quiet do
          Agreements::Broadcast.quiet do
            ApplicationRecord.transaction do
              TenantLock.acquire(@tenant_id)
              process_lot
            end
          end
        end
      end

      def process_lot
        rows = PaymentStream.payments_lot(@import, @cursor, self.class.lot_size)
        return false if rows.empty?

        context = lot_context
        new_payments = []
        updates = []
        credits = []
        allocations = []
        abatements = []
        context.states.start_lot
        context.settlement&.preload(rows.filter_map { |row| row["bill_id"]&.to_i }.uniq)
        context.flow.begin_lot(rows)
        context.agreements.begin_lot(rows)

        rows.each { |row| apply_row(row, context, new_payments: new_payments, updates: updates, credits: credits, allocations: allocations, abatements: abatements) }
        @cursor = [ rows.last["paid_on"].to_s, rows.last["rank"].to_i, rows.last["line"].to_i ]
        @done += rows.size
        unless @commit
          # A simulação também renova o avanço que a importação presa mede, mas só a cada 20 s: um aviso de andamento colado no aviso de "conferida" fazia a tela perder o último.
          show_progress
          return true
        end

        write(new_payments, updates, credits, context.states.lot, allocations, abatements)
        context.flow.flush
        touched = context.flow.touched.to_a | Promises::Evaluator.promises_of_bills(context.states.lot.keys)
        # R193, R196, R198: as promessas tocadas são avaliadas depois que o lote foi gravado (cumprida, cumprida com atraso, cancelada).
        Promises::Evaluator.new(@tenant_id).evaluate(touched) if touched.any?
        # 11, R229, R232: a situação dos acordos tocados (efetivação, cancelamento, em atraso, quitado) depois que o lote foi gravado.
        context.agreements.finalize if context.agreements.touched.any?
        save_state
        true
      end

      def show_progress
        return if Time.current - @progress_at < 20

        @progress_at = Time.current
        @import.update!(progress_percent: [ 75 + (20 * @done / [ @total, 1 ].max), 95 ].min, progress_label: "Simulando o efeito na carteira: #{@done} de #{@total} linhas")
      end

      # O que um lote usa: na conferência, um só durante toda a leitura (nada é gravado, então o que o arquivo aloca fica na memória); na confirmação, um novo por
      # lote, porque o banco (e quem mais gravou entre os lotes) é a única verdade.
      Context = Struct.new(:states, :settlement, :flow, :agreements, keyword_init: true)

      def lot_context
        return @context if @context && !@commit

        states = BillStates.new(@shared, keep_all: !@commit)
        # Credor com regra de encargos: o pagamento cobre o valor atualizado na data dele, encargos antes do principal (09, R226).
        settlement = Charges::Settlement.for(@import.tenant)
        @context = Context.new(states: states, settlement: settlement,
                               # Pagamentos com o número de uma promessa (10, R194): alocados nos títulos dela.
                               flow: Promises::PaymentFlow.new(@import.tenant, @setting, states, settlement),
                               # Pagamentos com o número de um título de acordo ou do acordo (11, R225 a R232): alocados nos títulos de acordo, com efetivação, mora e tolerância.
                               agreements: Agreements::PaymentFlow.new(@import.tenant, @setting, states, settlement))
      end

      # O cursor e o resumo do que já foi gravado, na transação do lote; o andamento sobe até 99% (o resto é do fim da confirmação).
      def save_state
        @import.update_columns(batch_state: { "cursor" => @cursor, "done" => @done, "effect" => @summary.to_h.stringify_keys })
        percent = @total.zero? ? 90 : [ 10 + (85 * @done / @total), 95 ].min
        @import.update!(progress_percent: percent, progress_label: "Gravando pagamentos: #{@done} de #{@total} linhas")
      end

      def apply_row(row, context, new_payments:, updates:, credits:, allocations:, abatements:)
        states = context.states
        settlement = context.settlement
        flow = context.flow
        agreements = context.agreements
        summary = @summary
        import = @import
        amount = row["amount_cents"].to_i
        if agreements.owns?(row) || (row["held_state"] == "awaiting_effectuation" && agreements.counts_as_agreement?(row)) ||
           (row["bill_id"] && agreements.rebate_oldest?(row, (states.get(row["bill_id"].to_i) || [ nil, row["bill_status"] ])[1]))
          return agreement_row(row, amount, agreements, summary, new_payments: new_payments, updates: updates, credits: credits, allocations: allocations, abatements: abatements, import: import)
        end
        return promise_row(row, amount, flow, summary, new_payments: new_payments, updates: updates, credits: credits, allocations: allocations, abatements: abatements, import: import) if row["promise_id"]

        if row["bill_id"].nil?
          # R52a: o título informado não está na carteira do credor: pendente, sem efeito e sem crédito.
          if row["src"].to_i == 1
            summary[:pending_new] += 1
            summary[:pending_cents] += amount
            new_payments << payment_row(import, row, nil, "pending", 0, 0)
          end
          return
        end

        bill_id = row["bill_id"].to_i
        paid, status, paid_on = states.get(bill_id) || [ row["paid_cents"].to_i, row["bill_status"], nil ]
        pay_date = row["paid_on"].is_a?(Date) ? row["paid_on"] : Date.parse(row["paid_on"].to_s)
        due = status == "active" ? settlement&.due(bill_id, pay_date, row["bill_amount"].to_i - paid) : nil
        result = Allocation.call(@setting, bill_amount: row["bill_amount"].to_i, status: status, paid: paid, amount: amount, due: due, final_state: row["final_state"])
        settlement&.record(bill_id, pay_date, result.components)
        agreements.original_paid(row) if row["held_state"] == "awaiting_effectuation" && result.applied.positive?
        paid += result.paid_principal
        if result.settled
          status = "paid"
          paid_on = row["paid_on"]
          summary[:settled] += 1
        elsif result.applied.positive?
          summary[:partial] += 1
        end
        states.put(bill_id, paid: paid, status: status, paid_on: paid_on, keep: row["repeats"].to_i > 1)
        summary[:applied_cents] += result.applied
        if result.credit.positive?
          summary[:credits] += 1
          summary[:credit_cents] += result.credit
        end

        # DP1: o pagamento direto a título de promessa aberta conta para ela, se o credor assim o quer e o meio e a data são os combinados.
        promise_id = flow.direct_promise_for(bill_id)
        counted = promise_id.present? && result.applied.positive? && flow.count_direct(promise_id, bill_id, row["payment_method"], pay_date, result.components)
        promise_id = nil unless counted
        if row["src"].to_i.zero?
          summary[:pending_applied] += 1
          updates << [ row["payment_id"].to_i, bill_id, result.applied, result.credit, promise_id, counted ]
        else
          new_payments << payment_row(import, row, bill_id, "applied", result.applied, result.credit, promise_id: promise_id, counted: counted)
        end
        key = row["src"].to_i.zero? ? row["payment_id"].to_i : [ row["channel_id"].to_i, row["identifier"] ]
        allocations << { key: key, bill_id: bill_id, components: result.components } if result.components.any?
        if result.abatement.any?
          # R226, R228a: a diferença dada por paga (estado final do credor ou tolerância) fica registrada por componente.
          abatements << { key: key, bill_id: bill_id, kind: result.abatement_kind, components: result.abatement }
          summary[:abated] += 1
          summary[:abated_cents] += result.abatement.values.sum
        end
        return unless result.credit.positive?

        credits << { contract_id: row["contract_id"].to_i, key: key, amount: result.credit, reason: result.reason }
      end

      # Pagamento a um número de promessa (10, R194): sem título; as alocações dizem em quais títulos caiu. Pode ser pagamento comum dos títulos dela.
      def promise_row(row, amount, flow, summary, new_payments:, updates:, credits:, allocations:, abatements:, import:)
        pay_date = row["paid_on"].is_a?(Date) ? row["paid_on"] : Date.parse(row["paid_on"].to_s)
        promise_id = row["promise_id"].to_i
        outcome = flow.settle(promise_id, amount: amount, pay_date: pay_date, method: row["payment_method"])
        summary[:promise_payments] += 1
        summary[:settled] += outcome.settled
        summary[:partial] += outcome.partial
        summary[:applied_cents] += outcome.applied
        if outcome.credit.positive?
          summary[:credits] += 1
          summary[:credit_cents] += outcome.credit
        end
        key = row["src"].to_i.zero? ? row["payment_id"].to_i : [ row["channel_id"].to_i, row["identifier"] ]
        if row["src"].to_i.zero?
          summary[:pending_applied] += 1
          updates << [ row["payment_id"].to_i, nil, outcome.applied, outcome.credit, promise_id, outcome.counted ]
        else
          new_payments << payment_row(import, row, nil, "applied", outcome.applied, outcome.credit, promise_id: promise_id, counted: outcome.counted)
        end
        outcome.allocations.each { |bill_id, components| allocations << { key: key, bill_id: bill_id, components: components } }
        outcome.abatements.each do |bill_id, kind, components|
          abatements << { key: key, bill_id: bill_id, kind: kind, components: components }
          summary[:abated] += 1
          summary[:abated_cents] += components.values.sum
        end
        credits << { contract_id: outcome.contract_id, key: key, amount: outcome.credit, reason: outcome.reason } if outcome.credit.positive?
      end

      # Pagamento a um título de acordo ou ao acordo (11, R227, R230): o pagamento fica no título quando só ele recebeu algo; senão, no acordo (como o da promessa).
      def agreement_row(row, amount, agreements, summary, new_payments:, updates:, credits:, allocations:, abatements:, import:)
        pay_date = row["paid_on"].is_a?(Date) ? row["paid_on"] : Date.parse(row["paid_on"].to_s)
        outcome =
          if row["bill_agreement_id"] then agreements.settle_title(row, amount, pay_date)
          elsif row["bill_origin_agreement_id"] then agreements.settle_reversal_title(row, amount, pay_date)
          elsif row["agreement_ref_id"] then agreements.settle_number(row, amount, pay_date)
          elsif row["held_state"] == "awaiting_effectuation" then agreements.settle_as_agreement(row, amount, pay_date)
          else agreements.settle_rebate_oldest(row, amount, pay_date)
          end
        summary[:agreement_payments] += 1
        summary[:settled] += outcome.settled
        summary[:partial] += outcome.partial
        summary[:applied_cents] += outcome.applied
        if outcome.credit.positive?
          summary[:credits] += 1
          summary[:credit_cents] += outcome.credit
        end
        bills = outcome.allocations.map(&:first).uniq
        bill_id = bills.size == 1 && outcome.target == bills.first ? bills.first : nil
        key = row["src"].to_i.zero? ? row["payment_id"].to_i : [ row["channel_id"].to_i, row["identifier"] ]
        if row["src"].to_i.zero?
          summary[:pending_applied] += 1
          updates << [ row["payment_id"].to_i, bill_id, outcome.applied, outcome.credit, nil, false, outcome.agreement_id ]
        else
          new_payments << payment_row(import, row, bill_id, "applied", outcome.applied, outcome.credit, agreement_id: outcome.agreement_id)
        end
        outcome.allocations.each { |bill, components| allocations << { key: key, bill_id: bill, components: components } }
        outcome.abatements.each do |bill, kind, components|
          abatements << { key: key, bill_id: bill, kind: kind, components: components }
          summary[:abated] += 1 unless kind == "early"
          summary[:abated_cents] += components.values.sum unless kind == "early"
        end
        credits << { contract_id: outcome.contract_id, key: key, amount: outcome.credit, reason: outcome.reason, bucket: outcome.bucket, agreement_id: (outcome.bucket ? outcome.agreement_id : nil) } if outcome.credit.positive?
      end

      def payment_row(import, row, bill_id, status, applied, credit, promise_id: nil, counted: false, agreement_id: nil)
        { agreement_id: agreement_id, final_state: row["final_state"], promise_id: promise_id, promise_counted: counted, channel_id: row["channel_id"].to_i, identifier: row["identifier"],
          document: row["document"], bill_number: row["bill_number"], bill_id: bill_id, paid_on: row["paid_on"], amount_cents: row["amount_cents"].to_i,
          payment_method: row["payment_method"], status: status, applied_cents: applied, credit_cents: credit, reversed_cents: 0, credit_reversed_cents: 0 }
      end

      # Grava o lote pelos modelos (validações e callbacks), na ordem: pagamentos novos, pendentes que viraram aplicados, créditos, alocações, abatimentos,
      # histórico (`Change.record_many!`) e os títulos.
      def write(new_payments, updates, credits, bill_states, allocations, abatements)
        import = @import
        tenant = import.tenant
        now = Time.current
        channels = PaymentChannel.where(id: new_payments.map { |attributes| attributes[:channel_id] }.uniq).index_by(&:id)
        created = new_payments.to_h do |attributes|
          [ [ attributes[:channel_id], attributes[:identifier] ],
            Payment.create!(**attributes.except(:channel_id), tenant: tenant, channel: channels.fetch(attributes[:channel_id]), import: import) ]
        end
        pending = known(Payment.where(id: updates.map(&:first)).preload(:channel), tenant)
        updates.each do |id, bill_id, applied, credit, promise_id, counted, agreement_id|
          pending.fetch(id).update!(bill_id: bill_id, status: "applied", applied_cents: applied, credit_cents: credit, promise_id: promise_id, promise_counted: counted,
                                    agreement_id: agreement_id, import: import)
        end
        payment_of = ->(key) { key.is_a?(Array) ? created.fetch(key) : pending.fetch(key) }

        bills = known(Bill.where(id: (bill_states.keys + allocations.map { |item| item[:bill_id] } + abatements.map { |item| item[:bill_id] }).uniq).preload(:contract, :customer), tenant)
        contracts = Contract.where(id: credits.map { |credit| credit[:contract_id] }.uniq).index_by(&:id)
        credits.each do |credit|
          Credit.create!(tenant: tenant, contract: contracts.fetch(credit[:contract_id]), payment: payment_of.call(credit[:key]), user_id: import.user_id, kind: "entry",
                         amount_cents: credit[:amount], reason: credit[:reason], bucket: credit[:bucket] || "available", agreement_id: credit[:agreement_id], occurred_at: now)
        end
        DetailLines.insert!(PaymentAllocation, allocations.flat_map do |allocation|
          payment = payment_of.call(allocation[:key])
          allocation[:components].map { |component, cents| PaymentAllocation.new(payment: payment, bill: bills.fetch(allocation[:bill_id]), component: component, amount_cents: cents) }
        end)
        DetailLines.insert!(Abatement, abatements.flat_map do |abatement|
          payment = payment_of.call(abatement[:key])
          abatement[:components].map do |component, cents|
            Abatement.new(tenant: tenant, payment: payment, bill: bills.fetch(abatement[:bill_id]), kind: abatement[:kind], component: component, amount_cents: cents)
          end
        end)

        changes = credits.map { |credit| [ contracts.fetch(credit[:contract_id]), "credit_added", { after: credit[:amount].to_s } ] } +
                  bill_states.map { |bill_id, bill| [ bills.fetch(bill_id), "payment_applied", { after: bill[:paid].to_s } ] } +
                  abatements.map { |abatement| [ bills.fetch(abatement[:bill_id]), "abated", { after: abatement[:components].values.sum.to_s } ] }
        Change.record_many!(changes, tenant_id: import.tenant_id, actor: import.user, import: import)

        bill_states.each { |bill_id, bill| bills.fetch(bill_id).update!(paid_cents: bill[:paid], status: bill[:status], paid_on: bill[:paid_on]) }
      end

      # Registros do lote lidos de uma vez, já com o credor ligado: a validação de cada `update!` não precisa buscar nada.
      def known(relation, tenant) = relation.each { |record| record.association(:tenant).target = tenant }.index_by(&:id)
  end
end
