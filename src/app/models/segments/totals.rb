module Segments
  # Quantos contratos e quanto saldo (em cobrança, sem encargos) há em cada segmento, por credor, para a aba Segmentos.
  # Consulta: `contracts (segment_id)` e `bills (contract_id)`.
  class Totals
    def initialize(tenants, today: Date.current)
      @tenants = tenants
      @today = today
    end

    # { segment_id => [contratos, saldo_em_centavos] }
    def call
      ids = @tenants.map(&:id)
      return {} if ids.empty?

      detail_only = TenantSetting.where(tenant_id: ids, upcoming_display: "detail_only").pluck(:tenant_id)
      Portfolio::Sql.rows(<<~SQL, detail_only.presence || [ 0 ], @today, ids).to_h { |row| [ row["segment_id"].to_i, [ row["contracts"].to_i, row["balance_cents"].to_i ] ] }
        select c.segment_id, count(distinct c.id) as contracts, coalesce(sum(greatest(b.amount_cents - b.paid_cents, 0)), 0) as balance_cents
        from contracts c
        left join bills b on b.contract_id = c.id and b.status = 'active' and (c.tenant_id not in (?) or b.due_date < ?::date)
        where c.tenant_id in (?) and c.segment_id is not null group by c.segment_id
      SQL
    end
  end
end
