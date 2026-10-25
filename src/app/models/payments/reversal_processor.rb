module Payments
  # Aplica (ou só simula) os estornos de uma importação (R60 a R63): o valor estornado sai primeiro do crédito que o pagamento gerou e,
  # depois, do título, que volta à cobrança sozinho se estava pago (R62, R62a).
  class ReversalProcessor
    CHUNK = 2000

    Sql = Portfolio::Sql

    # Chaves do resumo: reopened, credit_reduced, pending_reduced, from_bill_cents, from_credit_cents, reversed_cents.
    def run(import, commit:)
      tenant_id = import.tenant_id
      setting = TenantSetting.find_by!(tenant_id: tenant_id)
      summary = Hash.new(0)

      Sql.connection.execute("drop table if exists reversal_stream")
      Sql.run(<<~SQL, tenant_id, tenant_id, tenant_id, import.id)
        create temporary table reversal_stream on commit drop as
        select row_number() over (order by r.paid_on, r.line) as n, r.line, r.identifier, r.paid_on as reversed_on, r.amount_cents, r.reason,
               p.id as payment_id, p.channel_id, p.status as payment_status, p.amount_cents as payment_amount, p.applied_cents, p.credit_cents + p.moved_to_credit_cents as credit_cents,
               p.reversed_cents, p.credit_reversed_cents, p.bill_id, p.promise_id, p.agreement_id, b.kind as bill_kind, b.agreement_id as bill_agreement_id,
               (a.reversing_since is not null and a.reverted_at is null) as ag_reversing, a.state as ag_state, hold.agreement_id as held_agreement_id, hold.state as held_state, p.promise_counted, coalesce(b.contract_id, pr.contract_id, (select min(contract_id) from agreement_bills where agreement_id = p.agreement_id)) as contract_id, b.amount_cents as bill_amount, b.paid_cents, b.paid_on as bill_paid_on, b.status as bill_status, b.withdrawn_at
        from payment_rows r
        join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
        join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
        left join bills b on b.id = p.bill_id
        left join payment_promises pr on pr.id = p.promise_id
        left join agreements a on a.id = coalesce(b.agreement_id, p.agreement_id)
        left join (select ab.bill_id, ab.agreement_id, ha.state from agreement_bills ab join agreements ha on ha.id = ab.agreement_id where ab.held and ha.tenant_id = ?) hold on hold.bill_id = b.id
        where r.import_id = ? and r.ok
      SQL
      Sql.connection.execute("create unique index on reversal_stream (n)")
      Sql.connection.execute("analyze reversal_stream")
      total = Sql.one("select count(*) as n from reversal_stream")["n"].to_i

      payments = {}
      bills = {}
      parts = {} # por pagamento: o que ele ainda tem alocado em cada componente (09, R226); sem alocação, tudo é principal
      promise_parts = {} # por pagamento de promessa: o que ainda tem alocado em cada título e componente, na ordem da alocação (10, R199)
      promise_undo = {} # por promessa: o que o estorno tirou do que contava para ela, por título e componente
      touched_bill_ids = Set.new
      touched_promises = Set.new
      bill_meta = {}
      effects = Agreements::ReversalEffects.new(import, setting, summary) # 11, R233: espera do gestor, título de estorno, crédito usado ou transferido
      abatements = {} # por pagamento: os abatimentos que ainda valem, por título, tipo e componente (R226: o estorno os desfaz)
      (1..total).step(CHUNK) do |from|
        rows = Sql.rows("select * from reversal_stream where n between ? and ? order by n", from, from + CHUNK - 1)
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

        write(import, reversals, credits, changes, payments.slice(*touched_payments.keys), bills.slice(*touched_bills.keys), allocations, abatement_rows) if commit
      end
      # 11, R233: o que depende do lote já gravado (títulos de estorno, crédito usado, reavaliação dos acordos tocados).
      effects.finish! if commit
      if commit && (touched_promises.any? || touched_bill_ids.any?)
        undo_promise_counts(promise_undo)
        # R199: a promessa cumprida cujo pagamento foi estornado reabre no prazo, ou quebra.
        evaluator = Promises::Evaluator.new(tenant_id)
        evaluator.reassess((touched_promises.to_a + Promises::Evaluator.promises_of_bills(touched_bill_ids.to_a, states: %w[fulfilled fulfilled_late])).uniq)
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
            paid = Sql.one("select id, paid from payment_promise_bills where promise_id = ? and bill_id = ?", promise_id, bill_id) or next
            current = paid["paid"].is_a?(String) ? JSON.parse(paid["paid"]) : paid["paid"]
            components.each { |component, cents| current[component] = [ current.fetch(component, 0) - cents, 0 ].max }
            Sql.run("update payment_promise_bills set paid = ?::jsonb where id = ?", current.to_json, paid["id"].to_i)
          end
          Sql.run("update payment_promises set paid_cents = greatest(paid_cents - ?, 0), updated_at = now() where id = ?", by_bill.values.sum { |components| components.values.sum }, promise_id)
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

      REVERSAL_COLUMNS = %w[tenant_id channel_id payment_id import_id identifier reversed_on amount_cents from_credit_cents from_bill_cents reason created_at updated_at].freeze

      # Grava pelo COPY (ver Payments::Processor#write).
      def write(import, reversals, credits, changes, payments, bills, allocations, abatement_rows)
        now = Time.current
        Sql.copy_in("payment_reversals", REVERSAL_COLUMNS, reversals.map { |row| REVERSAL_COLUMNS.map { |column| row.fetch(column.to_sym) { now } } })
        Sql.copy_in("credits", %w[tenant_id contract_id payment_id user_id kind amount_cents reason occurred_at],
                    credits.map { |row| [ row[:tenant_id], row[:contract_id], row[:payment_id], row[:user_id], row[:kind], row[:amount_cents], row[:reason], row[:occurred_at] ] })
        Sql.copy_in("changes", %w[tenant_id user_id import_id subject_type subject_id event after occurred_at],
                    changes.map { |row| [ import.tenant_id, import.user_id, import.id, row[:subject_type], row[:subject_id], row[:event], row[:after], now ] })

        Sql.copy_in("payment_allocations", %w[payment_id bill_id component amount_cents created_at], allocations.map { |row| [ row[:payment_id], row[:bill_id], row[:component], row[:cents], now ] })
        Sql.copy_in("abatements", %w[tenant_id payment_id bill_id kind component amount_cents created_at], abatement_rows.map { |row| [ import.tenant_id, *row, now ] })

        payments.each_slice(CHUNK) do |slice|
          values = slice.map { |id, p| "(#{id.to_i}::bigint, #{p[:reversed].to_i}::bigint, #{p[:credit_reversed].to_i}::bigint, #{Sql.connection.quote(p[:status])}::varchar)" }.join(",")
          Sql.run("update payments set reversed_cents = v.reversed, credit_reversed_cents = v.credit_reversed, status = v.status, updated_at = now() " \
                  "from (values #{values}) as v(id, reversed, credit_reversed, status) where payments.id = v.id")
        end
        bills.each_slice(CHUNK) do |slice|
          values = slice.map { |id, b| "(#{id.to_i}::bigint, #{b[:paid].to_i}::bigint, #{Sql.connection.quote(b[:status])}::varchar, #{Sql.connection.quote(b[:paid_on])}::date)" }.join(",")
          Sql.run("update bills set paid_cents = v.paid, status = v.status, paid_on = v.paid_on, updated_at = now() " \
                  "from (values #{values}) as v(id, paid, status, paid_on) where bills.id = v.id")
        end
      end
  end
end
