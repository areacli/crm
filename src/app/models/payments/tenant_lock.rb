module Payments
  # Uma baixa por vez em cada credor (R10): o lote de uma importação e o pagamento que chega por webhook ou conciliação (`ExternalPayment`) pegam o mesmo
  # bloqueio consultivo da transação, então nunca gravam ao mesmo tempo sobre os mesmos títulos. O bloqueio dura a transação (um lote), não a importação.
  module TenantLock
    module_function

    def acquire(tenant_id)
      Portfolio::Sql.one("select pg_advisory_xact_lock(1, ?)::text as locked", tenant_id)
      true
    end
  end
end
