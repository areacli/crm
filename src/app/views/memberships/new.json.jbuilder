# Novo usuário na SPA (R36, R36a): os credores em que a pessoa gerencia usuários, cada um com os perfis dele.
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name, perfis: tenant.profiles.order(:name).map { |profile| { id: profile.id.to_s, nome: profile.name } } } })
