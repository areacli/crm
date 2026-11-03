# Usuários na SPA (R36, R40; decisão 0025): a busca, o filtro de credor e uma linha por vínculo, com as ações que valem para cada um.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.linhas @memberships do |membership|
  json.id membership.id
  json.nome "#{membership.user.name}#{" (você)" if membership.user_id == Current.user.id}"
  json.email membership.user.email_address
  json.credor membership.tenant.name
  json.perfil membership.profile.name
  json.partial! "memberships/selo", membership: membership
  json.proprio membership.user_id == Current.user.id
  json.ativo membership.active?
  json.nome_da_pessoa membership.user.name
end
