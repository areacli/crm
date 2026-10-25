module Promises
  # Promessas pendentes que o usuário pode aprovar (R192, R204): nos credores em que tem "registrar acionamentos" e consulta a carteira, com a alçada do perfil
  # dele no credor da promessa cobrindo o prazo pedido e nunca as que ele mesmo registrou. A lista e o número do menu usam a mesma consulta. Índice:
  # `payment_promises (tenant_id, state, promised_on)`.
  module Pending
    module_function

    def for(user)
      tenant_ids = user.tenant_ids_with("record_contact_attempts") & user.tenant_ids_with("view_portfolio")
      PaymentPromise.where(tenant_id: tenant_ids, state: "pending").where("payment_promises.user_id is distinct from ?", user.id).where(<<~SQL.squish, user.id)
        exists (select 1 from memberships m join promise_limits pl on pl.profile_id = m.profile_id join segments s on s.id = pl.segment_id
                where m.user_id = ? and m.tenant_id = payment_promises.tenant_id and m.active and pl.segment_id = payment_promises.segment_id
                  and least(pl.max_days, s.promise_max_days) >= (payment_promises.promised_on - payment_promises.contacted_on))
      SQL
    end
  end
end
