# Grupos das filas na SPA (15, R353, R358; decisão 0025): os grupos do credor, com os usuários (para a estratégia de cada um) e as filas em ordem.
json.credor_id @tenant.id.to_s
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.grupos @groups do |group|
  json.id group.id
  json.nome group.name
  json.usuarios(group.users.sort_by(&:name).map { |user| { id: user.id, nome: user.name } })
  json.filas(group.work_queues.map(&:name).join(" → ").presence || "—")
end
