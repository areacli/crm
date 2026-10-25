module Payments
  # Aplica (ou só simula) os pagamentos de uma importação sobre a carteira (R46, R46a, R50 a R53): em ordem de data de pagamento, com os
  # pendentes cujo título já existe (R52), em lotes. A conferência chama com `commit: false` e recebe os mesmos números que a confirmação
  # vai gravar. Entre a leitura do fluxo e a gravação, o credor está travado pela confirmação (bloqueio consultivo).
  class Processor
    CHUNK = 2000

    Sql = Portfolio::Sql

    # Chaves do resumo devolvido (todas inteiras): settled, partial, credits, credit_cents, pending_new, pending_applied, applied_cents,
    # pending_cents, promise_payments.
    def run(import, commit:)
      tenant_id = import.tenant_id
      setting = TenantSetting.find_by!(tenant_id: tenant_id)
      summary = Hash.new(0)
      build_stream(tenant_id, import.id)
      total = Sql.one("select count(*) as n from payment_stream")["n"].to_i

      # Estado dos títulos que recebem mais de um pagamento no fluxo e dos que pertencem a promessas: só esses precisam atravessar os lotes (guardar o
      # estado de todos estouraria a memória com 200 mil pagamentos); os demais usam o valor lido do banco.
      states = BillStates.new(Promises::PaymentFlow.shared_bill_ids(tenant_id))
      # Credor com regra de encargos: o pagamento cobre o valor atualizado na data dele, encargos antes do principal (09, R226).
      settlement = Charges::Settlement.for(import.tenant)
      # Pagamentos com o número de uma promessa (10, R194): alocados nos títulos dela.
      flow = Promises::PaymentFlow.new(import.tenant, setting, states, settlement)
      evaluate = Set.new
      (1..total).step(CHUNK) do |from|
        rows = Sql.rows("select * from payment_stream where n between ? and ? order by n", from, from + CHUNK - 1)
        new_payments = []
        updates = []
        credits = []
        allocations = []
        states.start_lot
        settlement&.preload(rows.filter_map { |row| row["bill_id"]&.to_i }.uniq)
        flow.begin_lot(rows)

        rows.each do |row|
          amount = row["amount_cents"].to_i
          if row["promise_id"]
            promise_row(row, amount, flow, summary, new_payments: new_payments, updates: updates, credits: credits, allocations: allocations, import: import)
            next
          end
          if row["bill_id"].nil?
            # R52a: o título informado não está na carteira do credor: pendente, sem efeito e sem crédito.
            if row["src"].to_i == 1
              summary[:pending_new] += 1
              summary[:pending_cents] += amount
              new_payments << payment_row(import, row, nil, "pending", 0, 0)
            end
            next
          end

          bill_id = row["bill_id"].to_i
          paid, status, paid_on = states.get(bill_id) || [ row["paid_cents"].to_i, row["bill_status"], nil ]
          pay_date = row["paid_on"].is_a?(Date) ? row["paid_on"] : Date.parse(row["paid_on"].to_s)
          due = status == "active" ? settlement&.due(bill_id, pay_date, row["bill_amount"].to_i - paid) : nil
          result = Allocation.call(setting, bill_amount: row["bill_amount"].to_i, status: status, paid: paid, amount: amount, due: due)
          settlement&.record(bill_id, pay_date, result.components)
          paid += result.principal
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
          next unless result.credit.positive?

          credits << { contract_id: row["contract_id"].to_i, key: key, amount: result.credit, reason: result.reason }
        end

        next unless commit

        write(import, new_payments, updates, credits, states.lot, allocations)
        flow.flush
        evaluate.merge(flow.touched)
        evaluate.merge(Promises::Evaluator.promises_of_bills(states.lot.keys))
      end
      # R193, R196, R198: as promessas tocadas são avaliadas depois que todos os lotes foram gravados (cumprida, cumprida com atraso, cancelada).
      Promises::Evaluator.new(tenant_id).evaluate(evaluate.to_a) if commit && evaluate.any?
      summary.to_h.symbolize_keys
    end

    private
      # Pagamento a um número de promessa (10, R194): sem título; as alocações dizem em quais títulos caiu. Pode ser pagamento comum dos títulos dela.
      def promise_row(row, amount, flow, summary, new_payments:, updates:, credits:, allocations:, import:)
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
        credits << { contract_id: outcome.contract_id, key: key, amount: outcome.credit, reason: outcome.reason } if outcome.credit.positive?
      end

      def payment_row(import, row, bill_id, status, applied, credit, promise_id: nil, counted: false)
        { tenant_id: import.tenant_id, promise_id: promise_id, promise_counted: counted, channel_id: row["channel_id"].to_i, import_id: import.id, identifier: row["identifier"], document: row["document"],
          bill_number: row["bill_number"], bill_id: bill_id, paid_on: row["paid_on"], amount_cents: row["amount_cents"].to_i,
          payment_method: row["payment_method"], status: status, applied_cents: applied, credit_cents: credit, reversed_cents: 0,
          credit_reversed_cents: 0 }
      end

      PAYMENT_COLUMNS = %w[tenant_id channel_id import_id identifier document bill_number bill_id paid_on amount_cents payment_method status applied_cents
                           credit_cents reversed_cents credit_reversed_cents promise_id promise_counted created_at updated_at].freeze

      # Grava pelo COPY (medido: o `insert_all!` do Active Record levava mais da metade da confirmação de 200 mil pagamentos).
      def write(import, new_payments, updates, credits, bills, allocations)
        now = Time.current
        Sql.copy_in("payments", PAYMENT_COLUMNS, new_payments.map { |row| PAYMENT_COLUMNS.map { |column| row.fetch(column.to_sym) { now } } })
        update_pending(import, updates)

        ids = payment_ids(import, credits + allocations)
        credit_rows = credits.map do |credit|
          payment_id = credit[:key].is_a?(Array) ? ids.fetch(credit[:key]) : credit[:key]
          [ import.tenant_id, credit[:contract_id], payment_id, import.user_id, "entry", credit[:amount], credit[:reason], now ]
        end
        Sql.copy_in("payment_allocations", %w[payment_id bill_id component amount_cents created_at],
                    allocations.flat_map do |allocation|
                      payment_id = allocation[:key].is_a?(Array) ? ids.fetch(allocation[:key]) : allocation[:key]
                      allocation[:components].map { |component, cents| [ payment_id, allocation[:bill_id], component, cents, now ] }
                    end)
        Sql.copy_in("credits", %w[tenant_id contract_id payment_id user_id kind amount_cents reason occurred_at], credit_rows)

        changes = credits.map { |credit| [ "contract", credit[:contract_id], "credit_added", credit[:amount].to_s ] } +
                  bills.map { |bill_id, bill| [ "bill", bill_id, "payment_applied", bill[:paid].to_s ] }
        Sql.copy_in("changes", %w[tenant_id user_id import_id subject_type subject_id event after occurred_at],
                    changes.map { |subject, id, event, after| [ import.tenant_id, import.user_id, import.id, subject, id, event, after, now ] })

        update_bills(bills)
      end

      # Ids dos pagamentos novos que geraram crédito ou alocação, pela chave (canal, identificador). Uma consulta por canal, pelo índice único
      # `payments (tenant_id, channel_id, identifier)`: sem o canal na consulta o índice não serve e cada lote varria os pagamentos do credor.
      def payment_ids(import, credits)
        keys = credits.filter_map { |credit| credit[:key] if credit[:key].is_a?(Array) }
        return {} if keys.empty?

        keys.group_by(&:first).flat_map do |channel_id, channel_keys|
          Sql.rows("select id, channel_id, identifier from payments where tenant_id = ? and channel_id = ? and identifier in (?)", import.tenant_id, channel_id, channel_keys.map(&:last))
        end.to_h { |row| [ [ row["channel_id"].to_i, row["identifier"] ], row["id"].to_i ] }
      end

      # Pendente cujo título passou a existir: vira aplicado (R52), com o que baixou e o que virou crédito.
      def update_pending(import, updates)
        updates.each_slice(CHUNK) do |slice|
          values = slice.map do |id, bill_id, applied, credit, promise_id, counted|
            "(#{id}::bigint, #{bill_id ? "#{bill_id.to_i}::bigint" : 'NULL::bigint'}, #{applied}::bigint, #{credit}::bigint, #{promise_id ? "#{promise_id.to_i}::bigint" : 'NULL::bigint'}, #{counted ? 'true' : 'false'})"
          end.join(",")
          Sql.run(<<~SQL, import.id)
            update payments set bill_id = v.bill_id, status = 'applied', applied_cents = v.applied, credit_cents = v.credit, promise_id = v.promise_id, promise_counted = v.counted,
                                import_id = ?, updated_at = now()
            from (values #{values}) as v(id, bill_id, applied, credit, promise_id, counted) where payments.id = v.id
          SQL
        end
      end

      def update_bills(bills)
        bills.each_slice(CHUNK) do |slice|
          quote = Sql.connection.method(:quote)
          values = slice.map { |id, bill| "(#{id.to_i}::bigint, #{bill[:paid].to_i}::bigint, #{quote.call(bill[:status])}::varchar, #{quote.call(bill[:paid_on])}::date)" }.join(",")
          Sql.run("update bills set paid_cents = v.paid, status = v.status, paid_on = v.paid_on, updated_at = now() " \
                  "from (values #{values}) as v(id, paid, status, paid_on) where bills.id = v.id")
        end
      end

      # Fluxo ordenado: as linhas novas da importação e os pagamentos pendentes (R52), por data e linha (R53).
      def build_stream(tenant_id, import_id)
        Sql.connection.execute("drop table if exists payment_stream")
        Sql.run(<<~SQL, tenant_id, import_id, tenant_id, tenant_id, tenant_id, tenant_id, tenant_id)
          create temporary table payment_stream on commit drop as
          select row_number() over (order by s.paid_on, s.src, s.line) as n,
                 s.src, s.line, s.payment_id, s.channel_id, s.identifier, s.document, s.bill_number, s.paid_on, s.amount_cents, s.payment_method,
                 case when pp.id is null then b.id end as bill_id, pp.id as promise_id, count(*) over (partition by b.id) as repeats, b.contract_id, b.amount_cents as bill_amount, b.paid_cents,
                 b.status as bill_status
          from (
            select 1 as src, r.line, null::bigint as payment_id, ch.id as channel_id, r.identifier, r.document, r.bill_number,
                   r.paid_on, r.amount_cents, r.payment_method
            from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            where r.import_id = ? and r.ok
            union all
            select 0, 0, p.id, p.channel_id, p.identifier, p.document, p.bill_number, p.paid_on, p.amount_cents - p.reversed_cents, p.payment_method
            from payments p where p.tenant_id = ? and p.status = 'pending' and p.amount_cents - p.reversed_cents > 0
          ) s
          left join customers c on c.tenant_id = ? and c.document = s.document
          left join bills bd on bd.tenant_id = ? and bd.customer_id = c.id and bd.number = s.bill_number
          -- R50a: o pagador pode ser um terceiro (o documento não é de cliente do título). Sem o título do documento, vale o título cujo número
          -- é único no credor; número que se repete entre clientes é ambíguo e o pagamento fica pendente.
          left join (select number, min(id) as id from bills where tenant_id = ? group by number having count(*) = 1) bn
            on bd.id is null and bn.number = s.bill_number
          left join bills b on b.id = coalesce(bd.id, bn.id)
          -- 10, R194: o número da promessa no lugar do número do título (DP8); único dentro do credor (MT-10).
          left join payment_promises pp on pp.tenant_id = ? and pp.number = s.bill_number
        SQL
        Sql.connection.execute("create unique index on payment_stream (n)")
        Sql.connection.execute("analyze payment_stream")
      end
  end
end
