module Promises
  # Título que sai da promessa por uma carga de carteira (10, R202, R202a): o retirado do batimento e o que a carga passa a outro contrato (a promessa não mistura
  # contratos, R183b). O valor da promessa diminui pelo valor do título, congelado por título (R187); sem nenhum título vigente, a promessa é cancelada.
  # Roda no fim da confirmação (decisão 0021): a consulta é de conjunto e a gravação é Active Record, em fatias de 1.000 linhas (uma transação cada), com a
  # auditoria única (`Change.record_many!`). É idempotente: o que já saiu não volta a sair.
  module BillExit
    SLICE = 1_000

    module_function

    def run(tenant_id)
      left = PaymentPromiseBill.joins(:promise, :bill).where(payment_promises: { tenant_id: tenant_id, state: %w[pending open] }, removed_at: nil)
                               .where("bills.status = 'withdrawn' OR bills.contract_id <> payment_promises.contract_id")
                               .pluck("payment_promise_bills.id", :promise_id, :bill_id, "bills.status")
      return if left.empty?

      ids = left.map { |_, promise_id, _, _| promise_id }.uniq
      Broadcast.quiet do
        left.each_slice(SLICE) { |slice| leave(tenant_id, slice) }
        ids.each_slice(SLICE) { |slice| recount(tenant_id, slice) }
        cancel_empty(tenant_id, ids)
      end
      Broadcast.changed(Tenant.find(tenant_id), customers_of(ids))
    end

    # As linhas saem da promessa com o motivo (retirado ou outro contrato).
    def leave(tenant_id, slice)
      lines = PaymentPromiseBill.where(id: slice.map(&:first)).preload(:promise, :bill).index_by(&:id)
      now = Time.current
      ApplicationRecord.transaction do
        entries = slice.map do |id, promise_id, bill_id, status|
          reason = status == "withdrawn" ? "withdrawn" : "contract"
          lines.fetch(id).update!(removed_at: now, held: false, removed_reason: reason)
          [ lines.fetch(id).promise, "bill_left", { field: "bill_id", before: bill_id.to_s, after: reason } ]
        end
        Change.record_many!(entries, tenant_id: tenant_id)
      end
    end

    # O valor da promessa é o dos títulos que continuam nela.
    def recount(tenant_id, promise_ids)
      totals = PaymentPromiseBill.where(promise_id: promise_ids, removed_at: nil).group(:promise_id).sum(:total_cents)
      ApplicationRecord.transaction do
        PaymentPromise.where(id: promise_ids).preload(:customer, :contract, :contact_attempt).each { |promise| promise.update!(total_cents: totals.fetch(promise.id, 0)) }
      end
    end

    # R202: retirados todos os títulos, a promessa é cancelada com o motivo; R202a: o que saiu por mudar de contrato tem motivo próprio.
    def cancel_empty(tenant_id, ids)
      empty = Portfolio::Sql.rows(<<~SQL, ids)
        select p.id, bool_and(pb.removed_reason = 'withdrawn') as only_withdrawn from payment_promises p join payment_promise_bills pb on pb.promise_id = p.id
        where p.id in (?) and not exists (select 1 from payment_promise_bills o where o.promise_id = p.id and o.removed_at is null) group by p.id
      SQL
      empty.group_by { |row| row["only_withdrawn"] == true || row["only_withdrawn"] == "t" }.each do |only_withdrawn, rows|
        reason = only_withdrawn ? "títulos fora da cobrança" : "título saiu do contrato"
        rows.map { |row| row["id"].to_i }.each_slice(SLICE) do |slice|
          promises = PaymentPromise.where(id: slice).preload(:customer, :contract, :contact_attempt).to_a
          ApplicationRecord.transaction do
            promises.each { |promise| promise.update!(state: "canceled", reason: reason, closed_at: Time.current, paid_percent: 0) }
            Change.record_many!(promises.map { |promise| [ promise, "state_changed", { field: "state", before: "open", after: "canceled", note: reason } ] }, tenant_id: tenant_id)
          end
        end
      end
    end

    def customers_of(ids)
      Portfolio::Sql.rows("select distinct cc.customer_id from payment_promises p join contract_customers cc on cc.contract_id = p.contract_id where p.id in (?)", ids.first(200)).map { |row| row["customer_id"].to_i }
    end
  end
end
