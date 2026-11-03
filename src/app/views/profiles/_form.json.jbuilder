# Formulário do perfil na SPA (R30; 14, R310): os credores (na criação), o nome, a marca de operação e as permissões com o número de cada uma.
json.credores((@tenants || []).map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.credor profile.tenant.name
json.credor_id profile.tenant_id.to_s
json.nome profile.name.to_s
json.de_operacao profile.available_to_operations?
json.permissoes(Permission::ALL.map { |key| { id: key, nome: "#{Permission.number(key)}. #{Permission.label(key)}" } })
json.marcadas profile.permissions
