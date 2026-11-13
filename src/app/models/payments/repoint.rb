module Payments
  # 17, R418: reenviar um pagamento PENDENTE com o mesmo método de recebimento e identificador e OUTRO sistema troca o sistema dele e o reavalia. A linha do
  # arquivo não vira pagamento novo (a identidade continua por método e identificador, R419): ela só aponta o pendente (`payment_rows.repoint_payment_id`),
  # que entra no fluxo da importação já no sistema novo. Com o mesmo sistema, ou com o pagamento já aplicado, a linha é "pagamento já registrado".
  module Repoint
    Sql = Portfolio::Sql

    module_function

    # Conferência, antes da regra do já registrado: marca as linhas de reenvio e as tira do fluxo, sem recusa. Nada muda no pagamento ainda.
    def mark(import)
      found = Sql.rows(<<~SQL, import.tenant_id, import.tenant_id, import.id)
        select r.line, p.id as payment_id
        from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
        join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.identifier
        where r.import_id = ? and r.ok and r.source_system_id is not null and p.status = 'pending' and p.source_system_id <> r.source_system_id
        order by r.line
      SQL
      found.each_slice(1000) do |slice|
        ApplicationRecord.transaction do
          slice.each { |row| PaymentRow.where(import_id: import.id, line: row["line"]).update_all(ok: false, repoint_payment_id: row["payment_id"]) }
        end
      end
    end

    # As linhas de reenvio da importação: `{ id do pagamento => [id do sistema, id do título no sistema, número do título] }`.
    def targets(import)
      PaymentRow.where(import_id: import.id).where.not(repoint_payment_id: nil).order(:line).pluck(:repoint_payment_id, :source_system_id, :external_bill_id, :bill_number)
                .to_h { |payment_id, *target| [ payment_id, target ] }
    end

    # Confirmação, antes de ordenar o fluxo: troca o sistema dos pendentes apontados. Repetir não muda nada (o pagamento já está no sistema novo).
    def apply(import)
      systems = Systems.new(import.tenant_id)
      targets(import).each_slice(500) do |slice|
        ApplicationRecord.transaction do
          TenantLock.acquire(import.tenant_id)
          payments = Payment.where(tenant_id: import.tenant_id, id: slice.map(&:first)).preload(:source_system).index_by(&:id)
          slice.each { |id, (system_id, external_id, number)| payments[id] && move(payments[id], systems.find(system_id), external_id, number, import: import) }
        end
      end
    end

    def due?(payment, system_id) = system_id.present? && payment.pending? && payment.source_system_id != system_id

    # Troca o sistema de um pendente, com histórico. O id do título é do sistema, então acompanha a troca; o número só entra quando o pagamento não tinha.
    def move(payment, system, external_id, number, import:)
      return false unless system && due?(payment, system.id)

      before = payment.source_system
      payment.update!(source_system: system, external_bill_id: external_id, bill_number: payment.bill_number.presence || number.to_s)
      Change.record!(payment, "system_changed", tenant_id: payment.tenant_id, actor: import.user, import: import, field: "source_system", before: before.name, after: system.name,
                                                 source_system_id: system.id)
      true
    end
  end
end
