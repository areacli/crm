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
        labels: brackets.labels, by_customer: distribution(brackets, by_customer), by_bill: distribution(brackets, by_bill) }
    end

    private
      def distribution(brackets, rows)
        by_index = rows.index_by { |row| row["idx"].to_i }
        brackets.brackets.each_index.map do |index|
          { label: brackets.label(index), count: by_index.dig(index, "n").to_i, cents: by_index.dig(index, "cents").to_i }
        end
      end
  end
end
