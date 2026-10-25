module Agreements
  # Cancelamentos automáticos do acordo aguardando efetivação por mudança nos originais (11, R240): título retirado numa carga ("título fora da cobrança") ou com o valor
  # vigente mudado ("valor do título mudou"). A parte paga da entrada é alocada nos originais, como na quebra (R235). Depois da efetivação, a carga não mexe nos
  # originais (M10). Roda dentro da transação da confirmação da carga.
  module BillExit
    module_function

    def run(tenant_id)
      rows = Portfolio::Sql.rows(<<~SQL, tenant_id)
        select distinct ab.agreement_id, case when b.status = 'withdrawn' then 'título fora da cobrança' else 'valor do título mudou' end as reason
        from agreement_bills ab join agreements a on a.id = ab.agreement_id join bills b on b.id = ab.bill_id
        where a.tenant_id = ? and a.state = 'awaiting_effectuation' and ab.held and (b.status = 'withdrawn' or b.amount_cents <> ab.amount_cents)
      SQL
      rows.uniq { |row| row["agreement_id"] }.each do |row|
        Release.new.call(Agreement.find(row["agreement_id"]), to: "canceled", reason: row["reason"], event: "canceled")
      end
    end
  end
end
