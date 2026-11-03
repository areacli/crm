# Perfis na SPA (R30 a R35; decisão 0025): o filtro de credor e os perfis da página com quantas permissões e usuários cada um tem.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.linhas @profiles do |profile|
  usuarios = @users_by_profile.fetch(profile.id, 0)
  json.id profile.id
  json.nome profile.name
  json.credor profile.tenant.name
  json.permissoes "#{profile.permissions.size} de #{Permission::ALL.size}"
  json.usuarios usuarios
  json.mensagem_de_excluir(usuarios.positive? ? "O perfil está em uso por #{usuarios} #{"usuário".pluralize(usuarios)} e não pode ser apagado." : "O perfil deixa de existir.")
end
