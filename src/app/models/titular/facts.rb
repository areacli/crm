module Titular
  # Fatos de cada contrato para a relação em aberto e o fim da última relação (07, R130a, R138a), em SQL de conjunto. Devolve o texto de uma
  # CTE `facts` com: contract_id, code, active_count, active_cents, withdrawn_cents (título retirado com saldo), credit_cents (livro mais
  # excedente calculado, 05 R90), last_on (última data de título que deixou de estar em aberto, pagamento, estorno ou lançamento de crédito)
  # e `open` (há relação em aberto). Os números inteiros vêm do código, nunca da tela.
  # Consultas e índices: `bills (contract_id)` e `bills (tenant_id, ...)`, `credits (contract_id)` e `(tenant_id)`, `payments (bill_id)`,
  # `payment_reversals (payment_id)`; a leitura por credor é uma varredura única, usada uma vez por dia.
  module Facts
    module_function

    def sql(tenant_ids: nil, contract_ids: nil)
      if contract_ids
        list = contract_ids.map(&:to_i).presence&.join(",") || "0"
        contracts, bills, credits, pay = "c.id in (#{list})", "contract_id in (#{list})", "contract_id in (#{list})", "b2.contract_id in (#{list})"
      else
        list = tenant_ids.map(&:to_i).presence&.join(",") || "0"
        contracts, bills, credits, pay = "c.tenant_id in (#{list})", "tenant_id in (#{list})", "tenant_id in (#{list})", "p.tenant_id in (#{list})"
      end
      <<~SQL
        facts as (
          select c.id as contract_id, c.code, coalesce(b.active_count, 0) as active_count, coalesce(b.active_cents, 0) as active_cents,
                 coalesce(b.withdrawn_cents, 0) as withdrawn_cents, coalesce(cr.credit_cents, 0) + coalesce(b.excess_cents, 0) as credit_cents,
                 greatest(b.last_on, cr.last_on, py.last_on, rv.last_on) as last_on,
                 (coalesce(b.active_count, 0) > 0 or coalesce(b.withdrawn_cents, 0) > 0 or coalesce(cr.credit_cents, 0) + coalesce(b.excess_cents, 0) > 0) as open
          from contracts c
          left join (select contract_id, count(*) filter (where status = 'active') as active_count,
                            coalesce(sum(greatest(amount_cents - paid_cents, 0)) filter (where status = 'active'), 0) as active_cents,
                            coalesce(sum(greatest(amount_cents - paid_cents, 0)) filter (where status = 'withdrawn'), 0) as withdrawn_cents,
                            coalesce(sum(greatest(paid_cents - amount_cents, 0)), 0) as excess_cents,
                            max(case when status = 'paid' then coalesce(paid_on, #{BrDate.sql_date('updated_at')})
                                     when status = 'withdrawn' and amount_cents <= paid_cents then #{BrDate.sql_date('withdrawn_at')} end) as last_on
                     from bills where #{bills} group by contract_id) b on b.contract_id = c.id
          left join (select contract_id, sum(amount_cents) as credit_cents, max(#{BrDate.sql_date('occurred_at')}) as last_on from credits where #{credits} group by contract_id) cr
            on cr.contract_id = c.id
          left join (select b2.contract_id, max(p.paid_on) as last_on from payments p join bills b2 on b2.id = p.bill_id where #{pay} group by b2.contract_id) py
            on py.contract_id = c.id
          left join (select b2.contract_id, max(r.reversed_on) as last_on from payment_reversals r join payments p on p.id = r.payment_id
                     join bills b2 on b2.id = p.bill_id where #{pay.sub('p.tenant_id', 'r.tenant_id')} group by b2.contract_id) rv on rv.contract_id = c.id
          where #{contracts}
        )
      SQL
    end
  end
end
