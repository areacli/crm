module Promises
  # Título que sai da promessa por uma carga de carteira (10, R202, R202a): o retirado do batimento e o que a carga passa a outro contrato (a promessa não mistura
  # contratos, R183b). O valor da promessa diminui pelo valor do título, congelado por título (R187); sem nenhum título vigente, a promessa é cancelada.
  # Roda dentro da transação da confirmação, em SQL de conjunto.
  module BillExit
    Sql = Portfolio::Sql

    module_function

    def run(tenant_id)
      left = Sql.rows(<<~SQL, tenant_id)
        update payment_promise_bills pb set removed_at = now(), held = false,
               removed_reason = case when b.status = 'withdrawn' then 'withdrawn' else 'contract' end
        from payment_promises p, bills b
        where pb.promise_id = p.id and pb.bill_id = b.id and p.tenant_id = ? and p.state in ('pending', 'open') and pb.removed_at is null
          and (b.status = 'withdrawn' or b.contract_id <> p.contract_id)
        returning pb.promise_id, pb.bill_id, pb.removed_reason
      SQL
      return if left.empty?

      ids = left.map { |row| row["promise_id"].to_i }.uniq
      Sql.run(<<~SQL, ids)
        update payment_promises p set total_cents = coalesce((select sum(pb.total_cents) from payment_promise_bills pb where pb.promise_id = p.id and pb.removed_at is null), 0), updated_at = now()
        where p.id in (?)
      SQL
      Sql.copy_in("changes", %w[tenant_id subject_type subject_id event field before after occurred_at],
                  left.map { |row| [ tenant_id, "payment_promise", row["promise_id"].to_i, "bill_left", "bill_id", row["bill_id"].to_s, row["removed_reason"], Time.current ] })
      cancel_empty(tenant_id, ids)
      Broadcast.changed(Tenant.find(tenant_id), customers_of(ids))
    end

    # R202: retirados todos os títulos, a promessa é cancelada com o motivo; R202a: o que saiu por mudar de contrato tem motivo próprio.
    def cancel_empty(tenant_id, ids)
      empty = Sql.rows(<<~SQL, ids)
        select p.id, bool_and(pb.removed_reason = 'withdrawn') as only_withdrawn from payment_promises p join payment_promise_bills pb on pb.promise_id = p.id
        where p.id in (?) and not exists (select 1 from payment_promise_bills o where o.promise_id = p.id and o.removed_at is null) group by p.id
      SQL
      empty.group_by { |row| row["only_withdrawn"] == true || row["only_withdrawn"] == "t" }.each do |only_withdrawn, rows|
        reason = only_withdrawn ? "títulos fora da cobrança" : "título saiu do contrato"
        slice_ids = rows.map { |row| row["id"].to_i }
        Sql.run("update payment_promises set state = 'canceled', reason = ?, closed_at = now(), paid_percent = 0, updated_at = now() where id in (?)", reason, slice_ids)
        Sql.copy_in("changes", %w[tenant_id subject_type subject_id event field before after note occurred_at],
                    slice_ids.map { |id| [ tenant_id, "payment_promise", id, "state_changed", "state", "open", "canceled", reason, Time.current ] })
      end
    end

    def customers_of(ids)
      Sql.rows("select distinct cc.customer_id from payment_promises p join contract_customers cc on cc.contract_id = p.contract_id where p.id in (?)", ids.first(200)).map { |row| row["customer_id"].to_i }
    end
  end
end
