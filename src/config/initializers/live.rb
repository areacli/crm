# Recursos do tempo real com dados da SPA (decisão 0025): cada um diz como carregar, para um usuário, os registros que ele vê, e a visão JSON.
Rails.application.config.to_prepare do
  # Clientes: a linha resumida do cliente; a ficha aberta se refaz quando o cliente dela muda (acionamento, promessa, acordo).
  Live.register("clientes", partial: "customers/live") { |user, ids| Customer.visible_to(user, "view_portfolio").where(id: ids).includes(:tenant) }
  # Importações: a situação e o andamento, para a lista e a página da importação.
  # Lotes de distribuição: a página do lote se refaz quando a conferência ou a confirmação termina.
  Live.register("lotes", partial: "distribution_batches/live") { |user, ids| DistributionBatch.visible_to(user, "distribute_portfolio").where(id: ids) }
  # Credores: as telas por credor (filas, enquadramento da distribuição, guarda de dados) se refazem quando algo do credor muda; a mensagem leva só o id.
  Live.register("credores", partial: "tenants/live") { |user, ids| Tenant.where(id: Membership.usable.where(user: user).select(:tenant_id)).where(id: ids) }
  Live.register("importacoes", partial: "imports/live") { |user, ids| Pundit.policy_scope!(user, Import).where(id: ids) }
end
