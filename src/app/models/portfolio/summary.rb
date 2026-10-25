module Portfolio
  # Resumo da carteira (R23): um só conjunto de totais, somados sobre os credores em que o usuário pode consultar a carteira (decisão do Paulo,
  # 25/10/2026; antes havia um resumo por credor, MT-20). Totais e duas distribuições por faixa de atraso, em tabela: por cliente (cada cliente
  # na faixa do título mais atrasado, com todo o seu vencido; visão da cobrança) e por título (cada título vencido na faixa do próprio atraso; visão
  # do financeiro). As faixas são configuradas por credor: as tabelas por faixa só existem quando os credores visíveis têm as mesmas faixas; se
  # diferirem, `labels`, `by_customer` e `by_bill` vêm nulos e a tela mostra uma nota. Todas as consultas são de conjunto, por lista de credores
  # (`tenant_id in (?)`, mesmos índices de antes), sem laço por credor; o que depende da configuração do credor (exibição do a vencer, política
  # do mês do estorno) é separado por política, também em consultas de conjunto.
  class Summary
    def initialize(user, reference: Date.current)
      @user = user
      @reference = reference
    end

    # Os totais de todos os credores em que o usuário pode consultar a carteira (V10: o que não tem a permissão fica fora da soma).
    def totals = compute(Tenant.includes(:setting).where(id: @user.tenant_ids_with("view_portfolio")).order(:name).to_a)

    # Os totais de um credor só (usado pelos testes e pelas medições).
    def for_tenant(tenant) = compute([ tenant ])

    private
      def compute(tenants)
        return nil if tenants.empty?

        ids = tenants.map(&:id)
        stored = tenants.map { |tenant| tenant.setting.aging_brackets }.uniq
        same_brackets = stored.size == 1
        brackets = AgingBrackets.from_stored(stored.first) if same_brackets
        totals = Sql.rows(<<~SQL, @reference, @reference, @reference, ids).to_h { |row| [ row["tenant_id"].to_i, row ] }
          select tenant_id, count(distinct customer_id) as customers, count(*) as bills,
                 coalesce(sum(greatest(amount_cents - paid_cents, 0)) filter (where due_date < ?::date), 0) as overdue_cents,
                 coalesce(sum(case when kind in ('agreement', 'break') then greatest(amount_cents - greatest(paid_cents, coalesce((composition->>'installment_interest')::bigint, 0)), 0)
                                  else greatest(amount_cents - paid_cents, 0) end) filter (where due_date >= ?::date), 0) as upcoming_cents, -- N7: título de acordo a vencer pela amortização que falta
                 count(distinct customer_id) filter (where due_date < ?::date) as customers_overdue
          from bills where tenant_id in (?) and status = 'active' group by tenant_id
        SQL
        # A exibição do a vencer é do credor: "só o detalhe" conta só os clientes com vencido e não mostra o a vencer. Com credores de exibições diferentes, o a vencer
        # (que não é comparável) não aparece; o resumo com "somando o a vencer" só vale quando todos os credores somam.
        displays = tenants.map { |tenant| tenant.setting.upcoming_display }
        detail_only = ->(tenant) { tenant.setting.upcoming_display == "detail_only" }
        customers = tenants.sum { |tenant| (totals[tenant.id] || {}).fetch(detail_only.call(tenant) ? "customers_overdue" : "customers", 0).to_i }
        sum = ->(key) { totals.values.sum { |row| row[key].to_i } }
        by_bill = by_customer = nil
        updated = valuations(ids, brackets)
        if same_brackets
          # A data de referência entra uma só vez, por parâmetro, numa CTE; as faixas a repetem em cada WHEN pela coluna.
          by_bill = Sql.rows(<<~SQL, @reference, ids)
            with r as (select ?::date as d)
            select #{brackets.sql_index('(r.d - due_date)')} as idx, count(*) as n, sum(greatest(amount_cents - paid_cents, 0)) as cents
            from bills, r where tenant_id in (?) and status = 'active' and due_date < r.d group by 1
          SQL
          by_customer = Sql.rows(<<~SQL, @reference, ids)
            with r as (select ?::date as d)
            select #{brackets.sql_index('max_days')} as idx, count(*) as n, sum(overdue) as cents from (
              select max(r.d - due_date) as max_days, sum(greatest(amount_cents - paid_cents, 0)) as overdue
              from bills, r where tenant_id in (?) and status = 'active' and due_date < r.d group by customer_id
            ) c group by 1
          SQL
        end
        { tenants: tenants.size, updated: updated, customers: customers, customers_overdue: sum.call("customers_overdue"), bills: sum.call("bills"),
          overdue_cents: sum.call("overdue_cents"), upcoming_cents: sum.call("upcoming_cents"),
          upcoming_display: displays.uniq.size == 1 ? displays.first : "mixed", same_brackets: same_brackets,
          labels: brackets&.labels, by_customer: brackets && distribution(brackets, by_customer, updated[:by_customer]), by_bill: brackets && distribution(brackets, by_bill, updated[:by_bill]) }
          .merge(payments(tenants)).merge(contacts: contacts(ids), promises: promises(ids), agreements: agreements(ids))
      end

    # O saldo devedor de um título de acordo (11, R225, N7): vencido, o devido de hoje com a mora (a linha de `bill_valuations`); a vencer, a amortização que falta, sem os juros do
    # parcelamento que ainda não correram (o pago cobre primeiro os juros do parcelamento, R227). Fragmento sobre `bills b left join bill_valuations v`, com a data de referência como `?`.
    AGREEMENT_BALANCE = "case when b.due_date >= ?::date then greatest(b.amount_cents - greatest(b.paid_cents, coalesce((b.composition->>'installment_interest')::bigint, 0)), 0) " \
                        "else coalesce(v.total_cents, greatest(b.amount_cents - b.paid_cents, 0)) end".freeze

    private
      # Valor atualizado dos credores (09, R176): total, por faixa (do cliente e do título) e por segmento do contrato, somado no banco sobre `bill_valuations` (soma dos credores visíveis; os segmentos de mesmo nome
      # somam, e as faixas só entram quando os credores têm as mesmas). Consulta: `bill_valuations (tenant_id)` e a chave de `bills`.
      def valuations(ids, brackets)
        total = Sql.one("select coalesce(sum(total_cents), 0) as cents, max(calculated_on) as on_date from bill_valuations where tenant_id in (?)", ids)
        by_bill = by_customer = {}
        by_bill = Sql.rows(<<~SQL, @reference, ids).to_h { |row| [ row["idx"].to_i, row["cents"].to_i ] } if brackets
          with r as (select ?::date as d)
          select #{brackets.sql_index('(r.d - b.due_date)')} as idx, sum(v.total_cents) as cents
          from bill_valuations v join bills b on b.id = v.bill_id, r where v.tenant_id in (?) group by 1
        SQL
        by_customer = Sql.rows(<<~SQL, @reference, ids).to_h { |row| [ row["idx"].to_i, row["cents"].to_i ] } if brackets
          with r as (select ?::date as d)
          select #{brackets.sql_index('max_days')} as idx, sum(total) as cents from (
            select max(r.d - b.due_date) as max_days, sum(v.total_cents) as total
            from bill_valuations v join bills b on b.id = v.bill_id, r where v.tenant_id in (?) group by b.customer_id
          ) c group by 1
        SQL
        segments = Sql.rows(<<~SQL, ids).map { |row| { name: row["name"] || I18n.t("segments.none"), customers: row["customers"].to_i, balance_cents: row["balance"].to_i, updated_cents: row["updated"].to_i } }
          select s.name, count(distinct b.customer_id) as customers, sum(v.principal_cents) as balance, sum(v.total_cents) as updated
          from bill_valuations v join bills b on b.id = v.bill_id join contracts c on c.id = b.contract_id left join segments s on s.id = c.segment_id
          where v.tenant_id in (?) group by s.name order by bool_or(s.catch_all) nulls first, min(s.position), s.name
        SQL
        { total_cents: total["cents"].to_i, calculated_on: total["on_date"], by_bill: by_bill, by_customer: by_customer, segments: segments }
      end

      # Acionamentos dos últimos 7 e 30 dias (04, R79), pela data do contato: número de acionamentos e de clientes acionados, no total e por
      # tipo de resultado; o cliente acionado mais de uma vez conta uma vez em cada tipo em que apareceu. Uma só leitura do índice
      # `contact_attempts (tenant_id, contacted_at)` nos 30 dias, agrupada por cliente e tipo e por cliente (GROUPING SETS); a linha sem tipo é o
      # total. Contar `count(distinct customer_id)` no SQL ordenava centenas de milhares de linhas em disco (2,2 s com 1 milhão de acionamentos
      # no Laravel); o agrupamento por cliente evita a ordenação.
      def contacts(ids)
        since7 = Time.current - 7.days
        since30 = Time.current - 30.days
        rows = Sql.rows(<<~SQL, since7, ids, since30)
          select result_kind, coalesce(sum(n7), 0) as attempts7, coalesce(sum(n30), 0) as attempts30,
                 count(*) filter (where n7 > 0) as customers7, count(*) as customers30
          from (
            select customer_id, result_kind, count(*) filter (where contacted_at >= ?) as n7, count(*) as n30
            from contact_attempts where tenant_id in (?) and contacted_at >= ?
            group by grouping sets ((customer_id, result_kind), (customer_id))
          ) g group by result_kind
        SQL
        [ [ 7, "7" ], [ 30, "30" ] ].map do |days, suffix|
          pick = ->(row) { { attempts: row["attempts#{suffix}"].to_i, customers: row["customers#{suffix}"].to_i } }
          { days: days, total: pick.call(rows.find { |row| row["result_kind"].nil? } || {}),
            kinds: ContactResult::KINDS.keys.index_with { |kind| pick.call(rows.find { |row| row["result_kind"] == kind.to_s } || {}) } }
        end
      end

      # Promessas dos últimos 7 e 30 dias (10, R205, DP4): clientes que prometeram e promessas feitas, pela data do registro, e as encerradas no período (cumpridas,
      # cumpridas com atraso à parte, e quebradas); canceladas, recusadas e não aprovadas ficam fora..
      # Consultas: `payment_promises (tenant_id, created_at)` e `(tenant_id, closed_at)`.
      def promises(ids)
        [ 7, 30 ].map do |days|
          since = Time.current - days.days
          made = Sql.one("select count(*) as promises, count(distinct customer_id) as customers from payment_promises where tenant_id in (?) and created_at >= ?", ids, since)
          closed = Sql.one(<<~SQL, ids, since)
            select count(*) filter (where state = 'fulfilled') as fulfilled, count(*) filter (where state = 'fulfilled_late') as late, count(*) filter (where state = 'broken') as broken
            from payment_promises where tenant_id in (?) and closed_at >= ? and state in ('fulfilled', 'fulfilled_late', 'broken')
          SQL
          { days: days, promises: made["promises"].to_i, customers: made["customers"].to_i, fulfilled: closed["fulfilled"].to_i, late: closed["late"].to_i, broken: closed["broken"].to_i }
        end
      end

      # Acordos do credor no mês corrente (11, R242): quanto está em acordo (títulos de acordo em cobrança, sem somar duas vezes), os aceitos, os ativos em dia e em atraso, os quebrados e
      # quitados, o desconto concedido por componente (contado na efetivação; o acordo cancelado depois da efetivação o tira no mês do cancelamento) por quem montou e por quem aprovou, e,
      # à parte, os abatimentos por tolerância, pelo credor e por mínimo. Consultas: `agreements (tenant_id, state, valid_until)` e `(tenant_id, created_at)`, `agreement_bills (agreement_id)`
      # e `abatements (tenant_id, created_at)`; o "em acordo" lê os títulos de acordo pelo índice parcial de `agreement_id`.
      def agreements(ids)
        from = @reference.beginning_of_month.in_time_zone
        to = from.next_month
        in_agreement = Sql.one("select coalesce(sum(#{AGREEMENT_BALANCE}), 0) as cents, count(distinct b.agreement_id) as n from bills b left join bill_valuations v on v.bill_id = b.id where b.tenant_id in (?) and b.status = 'active' and b.kind in ('agreement', 'break')", @reference, ids)
        accepted = Sql.one("select count(*) as n, coalesce(sum(value_cents), 0) as cents from agreements where tenant_id in (?) and accepted_at >= ? and accepted_at < ?", ids, from, to)
        states = Sql.rows("select state, count(*) as n from agreements where tenant_id in (?) and state in ('active_on_time', 'active_late') group by 1", ids).to_h { |row| [ row["state"], row["n"].to_i ] }
        broken = Sql.one("select count(*) as n from agreements where tenant_id in (?) and broken_at >= ? and broken_at < ? and broken_after_effectuation", ids, from, to)["n"].to_i
        settled = Sql.one("select count(*) as n from agreements where tenant_id in (?) and state = 'settled' and closed_at >= ? and closed_at < ?", ids, from, to)["n"].to_i
        discounts = Hash.new(0)
        by_user = Hash.new(0)
        by_approver = Hash.new(0)
        discount_rows = lambda do |condition, sign|
          Sql.rows(<<~SQL, ids, from, to).each do |row|
            select a.user_id, a.decided_by_id, d.key as component, sum(d.value::bigint) as cents
            from agreements a join agreement_bills ab on ab.agreement_id = a.id, jsonb_each_text(ab.discount) d
            where a.tenant_id in (?) and #{condition} group by 1, 2, 3
          SQL
            cents = sign * row["cents"].to_i
            discounts[row["component"]] += cents
            by_user[row["user_id"]&.to_i] += cents
            by_approver[row["decided_by_id"]&.to_i] += cents
          end
        end
        discount_rows.call("a.effectuated_at >= ? and a.effectuated_at < ?", 1)
        discount_rows.call("a.effectuated_at is not null and a.reverted_at >= ? and a.reverted_at < ?", -1)
        names = User.where(id: (by_user.keys + by_approver.keys).compact).pluck(:id, :name).to_h
        abatements = Sql.rows("select kind, coalesce(sum(amount_cents), 0) as cents from abatements where tenant_id in (?) and created_at >= ? and created_at < ? and kind <> 'early' group by 1", ids, from, to).to_h { |row| [ row["kind"], row["cents"].to_i ] }
        waiting = ReversalWait.where(tenant_id: ids, state: "waiting").count
        { label: I18n.l(@reference.beginning_of_month, format: "%B de %Y"), in_agreement_cents: in_agreement["cents"].to_i, in_agreement_count: in_agreement["n"].to_i,
          accepted: accepted["n"].to_i, accepted_cents: accepted["cents"].to_i, on_time: states.fetch("active_on_time", 0), late: states.fetch("active_late", 0), broken: broken, settled: settled,
          discounts: discounts.select { |_, cents| cents.nonzero? }, discount_total: discounts.values.sum,
          by_user: by_user.reject { |_, cents| cents.zero? }.map { |id, cents| [ names[id] || "—", cents ] }, by_approver: by_approver.reject { |_, cents| cents.zero? }.map { |id, cents| [ names[id] || "—", cents ] },
          abatements: abatements, waiting: waiting }
      end

      # Valor recuperado no mês corrente e no anterior, por meio de pagamento (R58, R64), crédito do credor (cada contrato uma vez, R55b)
      # e pagamentos pendentes. Crédito e pendente não contam como recuperado. O estorno desconta no mês que o credor escolheu (R64).
      # Consultas: `payments (tenant_id, paid_on)` e `payment_reversals (tenant_id, reversed_on)`; o pendente usa o índice parcial.
      def payments(tenant_list)
        ids = tenant_list.map(&:id)
        months = [ @reference.beginning_of_month, @reference.beginning_of_month.prev_month ]
        since = months.last
        recovered = months.map { |month| { month: month, label: I18n.l(month, format: "%B de %Y"), gross_cents: 0, total_cents: 0, methods: {} } }
        add = lambda do |method, month, cents, gross|
          entry = recovered.find { |item| item[:month] == month } or next
          entry[:methods][method] = entry[:methods].fetch(method, 0) + cents
          entry[:total_cents] += cents
          entry[:gross_cents] += cents if gross
        end

        Sql.rows(<<~SQL, ids, since).each { |row| add.call(row["payment_method"], Date.parse(row["month"].to_s), row["cents"].to_i, true) }
          select payment_method, date_trunc('month', paid_on)::date as month, sum(applied_cents) as cents from payments
          where tenant_id in (?) and status = 'applied' and paid_on >= ? group by 1, 2
        SQL
        # R90, R58: o excedente de título com valor reduzido não conta como recuperado. É tirado do mês e do meio do último pagamento do título
        # (aproximação: o excedente não tem pagamento próprio). Usa o índice parcial dos títulos com excedente e o de `payments (bill_id)`.
        Sql.rows(<<~SQL, ids, since).each { |row| add.call(row["payment_method"], Date.parse(row["month"].to_s), -row["cents"].to_i, true) }
          select lp.payment_method, date_trunc('month', lp.paid_on)::date as month, sum(b.paid_cents - b.amount_cents) as cents
          from bills b
          join lateral (select payment_method, paid_on from payments where bill_id = b.id and status = 'applied' order by paid_on desc, id desc limit 1) lp on true
          where b.tenant_id in (?) and b.paid_cents > b.amount_cents and lp.paid_on >= ? group by 1, 2
        SQL
        # A política do mês do estorno é do credor (R64): os credores de cada política entram em sua própria consulta de conjunto.
        tenant_list.group_by { |tenant| tenant.setting.reversal_month_policy_reversal? }.each do |by_reversal, group|
          column = by_reversal ? "r.reversed_on" : "p.paid_on"
          Sql.rows(<<~SQL, group.map(&:id), since).each { |row| add.call(row["payment_method"], Date.parse(row["month"].to_s), -row["cents"].to_i, false) }
            select p.payment_method, date_trunc('month', #{column})::date as month, sum(r.from_bill_cents) as cents
            from payment_reversals r join payments p on p.id = r.payment_id
            where r.tenant_id in (?) and #{column} >= ? group by 1, 2
          SQL
        end
        pending = Sql.one("select count(*) as n, coalesce(sum(amount_cents - reversed_cents), 0) as cents from payments where tenant_id in (?) and status = 'pending'", ids)
        ledger = ledger_credit_cents(ids)
        excess = excess_cents(ids)
        { recovered: recovered, credit_cents: ledger + excess, excess_cents: excess,
          pending_count: pending["n"].to_i, pending_cents: pending["cents"].to_i }
      end

      # Crédito do credor: o livro dos contratos (cada contrato uma vez) mais o excedente dos títulos de valor reduzido, calculado (05, R90).
      def ledger_credit_cents(ids) = Sql.one("select coalesce(sum(amount_cents), 0) as cents from credits where tenant_id in (?)", ids)["cents"].to_i

      # Consulta: índice parcial `bills (tenant_id) where paid_cents > amount_cents` (só os títulos com excedente).
      def excess_cents(ids)
        Sql.one("select coalesce(sum(paid_cents - amount_cents), 0) as cents from bills where tenant_id in (?) and paid_cents > amount_cents", ids)["cents"].to_i
      end

      def distribution(brackets, rows, updated = {})
        by_index = rows.index_by { |row| row["idx"].to_i }
        brackets.brackets.each_index.map do |index|
          { label: brackets.label(index), count: by_index.dig(index, "n").to_i, cents: by_index.dig(index, "cents").to_i, updated_cents: updated.fetch(index, 0) }
        end
      end
  end
end
