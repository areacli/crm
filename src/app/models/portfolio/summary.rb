module Portfolio
  # Resumo da carteira de cada credor (R23): totais e duas distribuições por faixa de atraso, em tabela: por cliente (cada cliente na faixa
  # do título mais atrasado, com todo o seu vencido; visão da cobrança) e por título (cada título vencido na faixa do próprio atraso; visão
  # do financeiro). Um resumo por credor, sem somar faixas de credores diferentes (MT-20).
  class Summary
    def initialize(user, reference: Date.current)
      @user = user
      @reference = reference
    end

    # Um item por credor em que o usuário pode consultar a carteira.
    def per_tenant
      Tenant.includes(:setting).where(id: @user.tenant_ids_with("view_portfolio")).order(:name).map { |tenant| for_tenant(tenant) }
    end

    def for_tenant(tenant)
      brackets = AgingBrackets.from_stored(tenant.setting.aging_brackets)
      totals = Sql.one(<<~SQL, @reference, @reference, @reference, tenant.id)
        select count(distinct customer_id) as customers, count(*) as bills,
               coalesce(sum(amount_cents - paid_cents) filter (where due_date < ?::date), 0) as overdue_cents,
               coalesce(sum(amount_cents - paid_cents) filter (where due_date >= ?::date), 0) as upcoming_cents,
               count(distinct customer_id) filter (where due_date < ?::date) as customers_overdue
        from bills where tenant_id = ? and status = 'active'
      SQL
      # A data de referência entra uma só vez, por parâmetro, numa CTE; as faixas a repetem em cada WHEN pela coluna.
      by_bill = Sql.rows(<<~SQL, @reference, tenant.id)
        with r as (select ?::date as d)
        select #{brackets.sql_index('(r.d - due_date)')} as idx, count(*) as n, sum(amount_cents - paid_cents) as cents
        from bills, r where tenant_id = ? and status = 'active' and due_date < r.d group by 1
      SQL
      by_customer = Sql.rows(<<~SQL, @reference, tenant.id)
        with r as (select ?::date as d)
        select #{brackets.sql_index('max_days')} as idx, count(*) as n, sum(overdue) as cents from (
          select max(r.d - due_date) as max_days, sum(amount_cents - paid_cents) as overdue
          from bills, r where tenant_id = ? and status = 'active' and due_date < r.d group by customer_id
        ) c group by 1
      SQL
      { tenant: tenant, customers: totals["customers"].to_i, customers_overdue: totals["customers_overdue"].to_i, bills: totals["bills"].to_i,
        overdue_cents: totals["overdue_cents"].to_i, upcoming_cents: totals["upcoming_cents"].to_i, upcoming_display: tenant.setting.upcoming_display,
        labels: brackets.labels, by_customer: distribution(brackets, by_customer), by_bill: distribution(brackets, by_bill) }.merge(payments(tenant)).merge(contacts: contacts(tenant))
    end

    private
      # Acionamentos dos últimos 7 e 30 dias (04, R79), pela data do contato: número de acionamentos e de clientes acionados, no total e por
      # tipo de resultado; o cliente acionado mais de uma vez conta uma vez em cada tipo em que apareceu. Uma só leitura do índice
      # `contact_attempts (tenant_id, contacted_at)` nos 30 dias, agrupada por cliente e tipo e por cliente (GROUPING SETS); a linha sem tipo é o
      # total. Contar `count(distinct customer_id)` no SQL ordenava centenas de milhares de linhas em disco (2,2 s com 1 milhão de acionamentos
      # no Laravel); o agrupamento por cliente evita a ordenação.
      def contacts(tenant)
        since7 = Time.current - 7.days
        since30 = Time.current - 30.days
        rows = Sql.rows(<<~SQL, since7, tenant.id, since30)
          select result_kind, coalesce(sum(n7), 0) as attempts7, coalesce(sum(n30), 0) as attempts30,
                 count(*) filter (where n7 > 0) as customers7, count(*) as customers30
          from (
            select customer_id, result_kind, count(*) filter (where contacted_at >= ?) as n7, count(*) as n30
            from contact_attempts where tenant_id = ? and contacted_at >= ?
            group by grouping sets ((customer_id, result_kind), (customer_id))
          ) g group by result_kind
        SQL
        [ [ 7, "7" ], [ 30, "30" ] ].map do |days, suffix|
          pick = ->(row) { { attempts: row["attempts#{suffix}"].to_i, customers: row["customers#{suffix}"].to_i } }
          { days: days, total: pick.call(rows.find { |row| row["result_kind"].nil? } || {}),
            kinds: ContactResult::KINDS.keys.index_with { |kind| pick.call(rows.find { |row| row["result_kind"] == kind.to_s } || {}) } }
        end
      end

      # Valor recuperado no mês corrente e no anterior, por meio de pagamento (R58, R64), crédito do credor (cada contrato uma vez, R55b)
      # e pagamentos pendentes. Crédito e pendente não contam como recuperado. O estorno desconta no mês que o credor escolheu (R64).
      # Consultas: `payments (tenant_id, paid_on)` e `payment_reversals (tenant_id, reversed_on)`; o pendente usa o índice parcial.
      def payments(tenant)
        months = [ @reference.beginning_of_month, @reference.beginning_of_month.prev_month ]
        since = months.last
        recovered = months.map { |month| { month: month, label: I18n.l(month, format: "%B de %Y"), gross_cents: 0, total_cents: 0, methods: {} } }
        add = lambda do |method, month, cents, gross|
          entry = recovered.find { |item| item[:month] == month } or next
          entry[:methods][method] = entry[:methods].fetch(method, 0) + cents
          entry[:total_cents] += cents
          entry[:gross_cents] += cents if gross
        end

        Sql.rows(<<~SQL, tenant.id, since).each { |row| add.call(row["payment_method"], Date.parse(row["month"].to_s), row["cents"].to_i, true) }
          select payment_method, date_trunc('month', paid_on)::date as month, sum(applied_cents) as cents from payments
          where tenant_id = ? and status = 'applied' and paid_on >= ? group by 1, 2
        SQL
        by_reversal = tenant.setting.reversal_month_policy_reversal?
        column = by_reversal ? "r.reversed_on" : "p.paid_on"
        Sql.rows(<<~SQL, tenant.id, since).each { |row| add.call(row["payment_method"], Date.parse(row["month"].to_s), -row["cents"].to_i, false) }
          select p.payment_method, date_trunc('month', #{column})::date as month, sum(r.from_bill_cents) as cents
          from payment_reversals r join payments p on p.id = r.payment_id
          where r.tenant_id = ? and #{column} >= ? group by 1, 2
        SQL
        pending = Sql.one("select count(*) as n, coalesce(sum(amount_cents - reversed_cents), 0) as cents from payments where tenant_id = ? and status = 'pending'", tenant.id)
        { recovered: recovered, credit_cents: Sql.one("select coalesce(sum(amount_cents), 0) as cents from credits where tenant_id = ?", tenant.id)["cents"].to_i,
          pending_count: pending["n"].to_i, pending_cents: pending["cents"].to_i }
      end

      def distribution(brackets, rows)
        by_index = rows.index_by { |row| row["idx"].to_i }
        brackets.brackets.each_index.map do |index|
          { label: brackets.label(index), count: by_index.dig(index, "n").to_i, cents: by_index.dig(index, "cents").to_i }
        end
      end
  end
end
