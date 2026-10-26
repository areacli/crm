module Payments
  # Aplica (ou só simula) os estornos de uma importação (R60 a R63): o valor estornado sai primeiro do crédito que o pagamento gerou e,
  # depois, do título, que volta à cobrança sozinho se estava pago (R62, R62a).
  #
  # Processamento em lote (decisão 0021): cada lote de `lot_size` estornos é uma transação travada pelo bloqueio por credor; as linhas são lidas do banco
  # naquele instante (`PaymentStream`), a gravação é Active Record e a auditoria é a única (`Change.record_many!`); o que depende do lote já gravado
  # (títulos de estorno, crédito usado, reavaliação das promessas e dos acordos) roda no fim do próprio lote. O cursor e o resumo parcial ficam em
  # `imports.batch_state`, na mesma transação, e a retomada continua do lote seguinte. Na conferência (`commit: false`) tudo fica na memória até o fim.
  class ReversalProcessor
    # Estornos por lote; atributo de classe para os testes de retomada usarem lotes pequenos.
    class_attribute :lot_size, instance_writer: false, default: 2000

    Sql = Portfolio::Sql

    # O que atravessa as linhas de um lote (na conferência, o arquivo todo; na confirmação, só o lote, porque o banco é a verdade entre os lotes).
    Memo = Struct.new(:payments, :bills, :parts, :promise_parts, :promise_undo, :touched_bill_ids, :touched_promises, :bill_meta, :effects, :abatements)

    # Chaves do resumo: reopened, credit_reduced, pending_reduced, from_bill_cents, from_credit_cents, reversed_cents.
    def run(import, commit:, step: nil)
      tenant_id = import.tenant_id
      setting = TenantSetting.find_by!(tenant_id: tenant_id)
      state = commit ? (import.reload.batch_state || {}) : {}
      summary = Hash.new(0).merge((state["effect"] || {}).symbolize_keys)
      cursor = state["cursor"]
      done = state.fetch("done", 0)
      total = PaymentRow.where(import_id: import.id, ok: true).count
      memo = nil
      lots = 0
      progress_at = Time.current

      lot = lambda do
        rows = PaymentStream.reversals_lot(import, cursor, self.class.lot_size)
        next false if rows.empty?

        memo = new_memo(import, setting, summary) if commit || memo.nil?
        payments, bills, parts, promise_parts, promise_undo, touched_bill_ids, touched_promises, bill_meta, effects, abatements = memo.to_a
        reversals = []
        credits = []
        changes = []
        touched_payments = {}
        touched_bills = {}
        allocations = []
        abatement_rows = []
        load_abatements(rows.map { |row| row["payment_id"].to_i }.uniq - abatements.keys, abatements)
        load_parts(rows.reject { |row| multi_bill?(row) }.map { |row| row["payment_id"].to_i }.uniq - parts.keys, parts)
        load_promise_parts(rows.select { |row| multi_bill?(row) }.map { |row| row["payment_id"].to_i }.uniq - promise_parts.keys, promise_parts)

        rows.each do |row|
          payment_id = row["payment_id"].to_i
          payment = payments[payment_id] ||= { reversed: row["reversed_cents"].to_i, credit_reversed: row["credit_reversed_cents"].to_i, status: row["payment_status"] }
          amount = row["amount_cents"].to_i
          summary[:reversed_cents] += amount
          from_credit = 0
          from_bill = 0

          route = effects.route(row)
          if route.kind == :wait
            # R233, AJ1: o efeito que a tabela de estornos não resolve espera o gestor; o título continua pago e nada muda até a decisão.
            effects.defer_wait(row, amount, route.reason) if commit
            payment[:reversed] += amount
            touched_payments[payment_id] = true
            reversals << { tenant_id: tenant_id, channel_id: row["channel_id"].to_i, payment_id: payment_id, import_id: import.id, identifier: row["identifier"],
                           reversed_on: row["reversed_on"], amount_cents: amount, from_credit_cents: 0, from_bill_cents: 0, reason: "à espera do gestor" }
            next
          elsif route.kind == :settlement
            # R230, AE9: o pagamento da quitação antecipada mantém ou desfaz a quitação.
            effects.defer_settlement(row, amount) if commit
            summary[:from_bill_cents] += amount
            payment[:reversed] += amount
            touched_payments[payment_id] = true
            reversals << { tenant_id: tenant_id, channel_id: row["channel_id"].to_i, payment_id: payment_id, import_id: import.id, identifier: row["identifier"],
                           reversed_on: row["reversed_on"], amount_cents: amount, from_credit_cents: 0, from_bill_cents: amount, reason: row["reason"] }
            next
          elsif route.kind == :renegotiated_original
            # AF3: o original já renegociado não volta à cobrança; nasce o título de estorno com o que o estorno tirou.
            taken = take(parts[payment_id], amount)
            taken.each { |component, cents| allocations << { payment_id: payment_id, bill_id: row["bill_id"].to_i, component: component, cents: -cents } }
            effects.defer_reversal_title(row, taken) if commit
            summary[:from_bill_cents] += amount
            payment[:reversed] += amount
            touched_payments[payment_id] = true
            reversals << { tenant_id: tenant_id, channel_id: row["channel_id"].to_i, payment_id: payment_id, import_id: import.id, identifier: row["identifier"],
                           reversed_on: row["reversed_on"], amount_cents: amount, from_credit_cents: 0, from_bill_cents: amount, reason: row["reason"] }
            next
          end

          promise_payment = multi_bill?(row)
          if row["bill_id"].nil? && !promise_payment
            # Pagamento pendente estornado deixa de ser pendente pelo valor estornado (R62).
            summary[:pending_reduced] += 1
          elsif promise_payment
            # 10, R199: pagamento de promessa; o estorno desfaz a alocação nos títulos dela, o último alocado primeiro, e a promessa é reavaliada depois.
            from_credit = [ amount, row["credit_cents"].to_i - payment[:credit_reversed] ].min
            from_bill = amount - from_credit
            payment[:credit_reversed] += from_credit
            if from_credit.positive?
              summary[:credit_reduced] += 1
              summary[:from_credit_cents] += from_credit
              plan = effects.plan_credit(row, from_credit)
              credits << { tenant_id: tenant_id, contract_id: row["contract_id"].to_i, payment_id: payment_id, user_id: import.user_id, kind: "reversal",
                           amount_cents: -plan.available, reason: "reversed", occurred_at: Time.current } if plan.available.positive?
            end
            if from_bill.positive?
              summary[:from_bill_cents] += from_bill
              promise_id = row["promise_id"].to_i
              touched_promises << promise_id if promise_id.positive?
              promise_take(promise_parts[payment_id], from_bill).each do |bill_id, component, cents|
                allocations << { payment_id: payment_id, bill_id: bill_id, component: component, cents: -cents }
                bill = bills[bill_id] ||= load_bill(bill_id, bill_meta)
                bill[:paid] -= undo_abatements(payment_id, bill_id, abatements, abatement_rows, all: agreement_bill?(bill_id, bill_meta))
                bill[:paid] -= cents if component == "principal" || (component != "late" && agreement_bill?(bill_id, bill_meta))
                if bill[:status] == "paid" && bill[:paid] < bill_meta.fetch(bill_id)[:amount]
                  bill[:status] = bill_meta[bill_id][:withdrawn_at].present? && setting.withdrawn_reversal_policy_withdrawn? ? "withdrawn" : "active"
                  bill[:paid_on] = nil
                  summary[:reopened] += 1
                end
                touched_bills[bill_id] = true
                touched_bill_ids << bill_id
                effects.note_reopened(bill_id, bill_meta[bill_id][:agreement_id], Date.iso8601(row["reversed_on"].to_s)) if agreement_bill?(bill_id, bill_meta)
                changes << { subject_type: "bill", subject_id: bill_id, event: "payment_reversed", after: bill[:paid].to_s }
                ((promise_undo[promise_id] ||= {})[bill_id] ||= Hash.new(0))[component] += cents if promise_id.positive? && row["promise_counted"] == true || row["promise_counted"] == "t"
              end
            end
          else
            from_credit = [ amount, row["credit_cents"].to_i - payment[:credit_reversed] ].min
            from_bill = amount - from_credit
            payment[:credit_reversed] += from_credit
            if from_credit.positive?
              summary[:credit_reduced] += 1
              summary[:from_credit_cents] += from_credit
              plan = effects.plan_credit(row, from_credit)
              credits << { tenant_id: tenant_id, contract_id: row["contract_id"].to_i, payment_id: payment_id, user_id: import.user_id, kind: "reversal",
                           amount_cents: -plan.available, reason: "reversed", occurred_at: Time.current } if plan.available.positive?
            end
            if from_bill.positive?
              bill_id = row["bill_id"].to_i
              bill = bills[bill_id] ||= { paid: row["paid_cents"].to_i, status: row["bill_status"], paid_on: row["bill_paid_on"] }
              agreement_title = row["bill_kind"].present? && row["bill_kind"] != "common"
              bill[:paid] -= undo_abatements(payment_id, bill_id, abatements, abatement_rows, all: agreement_title)
              # R226: o estorno desfaz a alocação na ordem inversa da baixa (principal, correção, honorários, multa, juros); só o principal mexe no saldo.
              taken = take(parts[payment_id], from_bill)
              taken.each { |component, cents| allocations << { payment_id: payment_id, bill_id: bill_id, component: component, cents: -cents } }
              # DP1: o pagamento direto que contou para uma promessa deixa de contar pelo que o estorno tirou.
              if row["promise_id"] && (row["promise_counted"] == true || row["promise_counted"] == "t")
                touched_promises << row["promise_id"].to_i
                taken.each { |component, cents| ((promise_undo[row["promise_id"].to_i] ||= {})[bill_id] ||= Hash.new(0))[component] += cents }
              end
              touched_bill_ids << bill_id
              bill[:paid] -= agreement_title ? taken.sum { |component, cents| component == "late" ? 0 : cents } : taken.fetch("principal", 0)
              summary[:from_bill_cents] += from_bill
              # R92: o estorno consome primeiro o excedente (valor reduzido abaixo do alocado); o título só volta à cobrança se o saldo reabre.
              if bill[:status] == "paid" && bill[:paid] < row["bill_amount"].to_i
                # R62a: o título que o credor tinha retirado segue a política; os demais voltam à cobrança.
                bill[:status] = row["withdrawn_at"].present? && setting.withdrawn_reversal_policy_withdrawn? ? "withdrawn" : "active"
                bill[:paid_on] = nil
                summary[:reopened] += 1
              end
              touched_bills[bill_id] = true
              changes << { subject_type: "bill", subject_id: bill_id, event: "payment_reversed", after: bill[:paid].to_s }
              effects.note_reopened(bill_id, row["bill_agreement_id"]&.to_i, Date.iso8601(row["reversed_on"].to_s)) if agreement_title
            end
          end

          payment[:reversed] += amount
          payment[:status] = "cancelled" if row["bill_id"].nil? && row["promise_id"].nil? && row["agreement_id"].nil? && payment[:reversed] >= row["payment_amount"].to_i
          touched_payments[payment_id] = true
          reversals << { tenant_id: tenant_id, channel_id: row["channel_id"].to_i, payment_id: payment_id, import_id: import.id, identifier: row["identifier"],
                         reversed_on: row["reversed_on"], amount_cents: amount, from_credit_cents: from_credit, from_bill_cents: from_bill, reason: row["reason"] }
        end

        cursor = [ rows.last["reversed_on"].to_s, rows.last["rank"].to_i, rows.last["line"].to_i ]
        done += rows.size
        unless commit
          # Só a cada 20 s (ver `Payments::Processor#show_progress`).
          if Time.current - progress_at >= 20
            progress_at = Time.current
            import.update!(progress_percent: [ 75 + (20 * done / [ total, 1 ].max), 95 ].min, progress_label: "Simulando o efeito na carteira: #{done} de #{total} linhas")
          end
          next true
        end

        write(import, reversals, credits, changes, payments.slice(*touched_payments.keys), bills.slice(*touched_bills.keys), allocations, abatement_rows)
        # 11, R233: o que depende do lote já gravado (títulos de estorno, crédito usado, reavaliação dos acordos tocados).
        effects.finish!
        if touched_promises.any? || touched_bill_ids.any?
          undo_promise_counts(promise_undo)
          # R199: a promessa cumprida cujo pagamento foi estornado reabre no prazo, ou quebra.
          Promises::Evaluator.new(tenant_id).reassess((touched_promises.to_a + Promises::Evaluator.promises_of_bills(touched_bill_ids.to_a, states: %w[fulfilled fulfilled_late])).uniq)
        end
        save_state(import, cursor, done, total, summary)
        true
      end

      loop do
        more = if commit
          Promises::Broadcast.quiet { Agreements::Broadcast.quiet { ApplicationRecord.transaction { TenantLock.acquire(tenant_id) && lot.call } } }
        else
          lot.call
        end
        break unless more

        lots += 1
        step&.set!(lots)
      end
      summary.to_h.symbolize_keys
    end

    private
      REMOVAL_ORDER = %w[principal correction fees fine interest installment_interest late].freeze

      # Quanto cada componente ainda tem alocado nos pagamentos: soma das linhas de alocação, que já inclui os estornos anteriores.
      def load_parts(payment_ids, parts)
        return if payment_ids.empty?

        payment_ids.each { |id| parts[id] = nil }
        Sql.rows("select payment_id, component, sum(amount_cents)::bigint as cents from payment_allocations where payment_id in (?) group by 1, 2", payment_ids).each do |row|
          (parts[row["payment_id"].to_i] ||= {})[row["component"]] = row["cents"].to_i
        end
      end

      # Alocação que cada pagamento de promessa ainda tem em cada título e componente; a ordem dos títulos é a da alocação (10, R199).
      def load_promise_parts(payment_ids, promise_parts)
        return if payment_ids.empty?

        payment_ids.each { |id| promise_parts[id] = [] }
        Sql.rows("select payment_id, bill_id, component, sum(amount_cents)::bigint as cents, min(id) as first_id from payment_allocations where payment_id in (?) group by 1, 2, 3 order by 1, 5",
                 payment_ids).each do |row|
          promise_parts[row["payment_id"].to_i] << { bill_id: row["bill_id"].to_i, component: row["component"], cents: row["cents"].to_i, first_id: row["first_id"].to_i }
        end
      end

      # Desfaz `amount` do pagamento de promessa: o último título alocado primeiro e, em cada um, o último componente primeiro. Devolve [título, componente, centavos].
      def promise_take(entries, amount)
        taken = []
        entries.sort_by { |entry| [ -entry[:first_id].to_i ] }.group_by { |entry| entry[:bill_id] }.each_value do |bill_entries|
          REMOVAL_ORDER.each do |component|
            entry = bill_entries.find { |item| item[:component] == component } or next
            part = [ amount, entry[:cents] ].min
            next unless part.positive?

            entry[:cents] -= part
            amount -= part
            taken << [ entry[:bill_id], component, part ]
          end
          break if amount <= 0
        end
        taken
      end

      # Abatimentos que cada pagamento ainda tem (soma das linhas, que já inclui os desfeitos); um por título, tipo e componente.
      def load_abatements(payment_ids, loaded)
        return if payment_ids.empty?

        payment_ids.each { |id| loaded[id] = [] }
        Sql.rows("select payment_id, bill_id, kind, component, sum(amount_cents)::bigint as cents from abatements where payment_id in (?) group by 1, 2, 3, 4", payment_ids).each do |row|
          loaded[row["payment_id"].to_i] << { bill_id: row["bill_id"].to_i, kind: row["kind"], component: row["component"], cents: row["cents"].to_i }
        end
      end

      # R226: o estorno do pagamento que deu origem a um abatimento o desfaz (linhas negativas) e o título volta a ser devido. Devolve o principal
      # abatido que sai do pago do título.
      def undo_abatements(payment_id, bill_id, loaded, rows, all: false)
        (loaded[payment_id] || []).select { |entry| entry[:bill_id] == bill_id && entry[:cents].positive? }.sum do |entry|
          cents = entry[:cents]
          rows << [ payment_id, bill_id, entry[:kind], entry[:component], -cents ]
          entry[:cents] = 0
          (entry[:component] == "principal" || (all && entry[:component] != "late")) ? cents : 0
        end
      end

      # Pagamento com mais de um título (de promessa ou de acordo): sem título próprio, a alocação diz onde caiu o dinheiro.
      def multi_bill?(row) = row["bill_id"].nil? && (row["promise_id"] || row["agreement_id"])

      def agreement_bill?(bill_id, meta) = meta.fetch(bill_id, {})[:kind].present? && meta[bill_id][:kind] != "common"

      def load_bill(bill_id, meta)
        row = Sql.one("select amount_cents, paid_cents, status, paid_on, withdrawn_at, kind, agreement_id from bills where id = ?", bill_id)
        meta[bill_id] = { amount: row["amount_cents"].to_i, withdrawn_at: row["withdrawn_at"], kind: row["kind"], agreement_id: row["agreement_id"]&.to_i }
        { paid: row["paid_cents"].to_i, status: row["status"], paid_on: row["paid_on"] }
      end

      # O que o estorno tirou do que contava para a promessa sai do valor alocado dela (por título e componente) e do total pago (10, R199).
      def undo_promise_counts(undo)
        undo.each do |promise_id, by_bill|
          by_bill.each do |bill_id, components|
            line = PaymentPromiseBill.find_by(promise_id: promise_id, bill_id: bill_id) or next
            current = line.paid.is_a?(String) ? JSON.parse(line.paid) : (line.paid || {}).dup
            components.each { |component, cents| current[component] = [ current.fetch(component, 0) - cents, 0 ].max }
            line.update!(paid: current)
          end
          promise = PaymentPromise.find(promise_id)
          promise.update!(paid_cents: [ promise.paid_cents - by_bill.values.sum { |components| components.values.sum }, 0 ].max)
        end
      end

      # Tira `amount` dos componentes do pagamento na ordem inversa da baixa; o que passa do alocado (pagamento sem alocação, de antes dos encargos)
      # sai do principal.
      def take(parts, amount)
        taken = {}
        if parts
          REMOVAL_ORDER.each do |component|
            part = [ amount, parts.fetch(component, 0) ].min
            next unless part.positive?

            taken[component] = part
            parts[component] -= part
            amount -= part
          end
        end
        taken["principal"] = taken.fetch("principal", 0) + amount if amount.positive?
        taken
      end

      def new_memo(import, setting, summary)
        Memo.new({}, {}, {}, {}, {}, Set.new, Set.new, {}, Agreements::ReversalEffects.new(import, setting, summary), {})
      end

      # O cursor e o resumo do que já foi gravado, na transação do lote; o andamento sobe até 95% (o resto é do fim da confirmação).
      def save_state(import, cursor, done, total, summary)
        import.update_columns(batch_state: { "cursor" => cursor, "done" => done, "effect" => summary.to_h.stringify_keys })
        return unless import.confirming?

        percent = total.zero? ? 90 : [ 10 + (85 * done / total), 95 ].min
        import.update!(progress_percent: percent, progress_label: "Gravando estornos: #{done} de #{total} linhas")
      end

      # Grava o lote pelos modelos (validações e callbacks), na ordem: estornos, créditos, alocações, abatimentos, histórico (`Change.record_many!`),
      # pagamentos e títulos.
      def write(import, reversals, credits, changes, payments, bills, allocations, abatement_rows)
        tenant = import.tenant
        payment_ids = reversals.map { |row| row[:payment_id] } + credits.map { |row| row[:payment_id] } + allocations.map { |row| row[:payment_id] } +
                      abatement_rows.map(&:first) + payments.keys
        payment_of = known(Payment.where(id: payment_ids.uniq).preload(:channel), tenant)
        bill_of = known(Bill.where(id: (allocations.map { |row| row[:bill_id] } + abatement_rows.map { |row| row[1] } + bills.keys + changes.map { |row| row[:subject_id] }).uniq).preload(:contract, :customer), tenant)
        channel_of = PaymentChannel.where(id: reversals.map { |row| row[:channel_id] }.uniq).index_by(&:id)
        contract_of = Contract.where(id: credits.map { |row| row[:contract_id] }.uniq).index_by(&:id)

        reversals.each do |row|
          PaymentReversal.create!(tenant: tenant, channel: channel_of.fetch(row[:channel_id]), payment: payment_of.fetch(row[:payment_id]), import: import, identifier: row[:identifier],
                                  reversed_on: row[:reversed_on], amount_cents: row[:amount_cents], from_credit_cents: row[:from_credit_cents], from_bill_cents: row[:from_bill_cents],
                                  reason: row[:reason])
        end
        credits.each do |row|
          Credit.create!(tenant: tenant, contract: contract_of.fetch(row[:contract_id]), payment: payment_of.fetch(row[:payment_id]), user_id: row[:user_id], kind: row[:kind],
                         amount_cents: row[:amount_cents], reason: row[:reason], occurred_at: row[:occurred_at])
        end
        DetailLines.insert!(PaymentAllocation, allocations.map do |row|
          PaymentAllocation.new(payment: payment_of.fetch(row[:payment_id]), bill: bill_of.fetch(row[:bill_id]), component: row[:component], amount_cents: row[:cents])
        end)
        DetailLines.insert!(Abatement, abatement_rows.map do |payment_id, bill_id, kind, component, cents|
          Abatement.new(tenant: tenant, payment: payment_of.fetch(payment_id), bill: bill_of.fetch(bill_id), kind: kind, component: component, amount_cents: cents)
        end)
        Change.record_many!(changes.map { |row| [ bill_of.fetch(row[:subject_id]), row[:event], { after: row[:after] } ] }, tenant_id: import.tenant_id, actor: import.user, import: import)

        payments.each { |id, row| payment_of.fetch(id).update!(reversed_cents: row[:reversed], credit_reversed_cents: row[:credit_reversed], status: row[:status]) }
        bills.each { |id, row| bill_of.fetch(id).update!(paid_cents: row[:paid], status: row[:status], paid_on: row[:paid_on]) }
      end

      # Registros do lote lidos de uma vez, já com o credor ligado: a validação de cada `update!` não precisa buscar nada.
      def known(relation, tenant) = relation.each { |record| record.association(:tenant).target = tenant }.index_by(&:id)
  end
end
