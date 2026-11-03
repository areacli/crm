# Perfis do credor do vínculo, para "Editar o perfil" (R32).
json.descricao "#{@membership.user.name} em #{@membership.tenant.name}."
json.perfil_id @membership.profile_id.to_s
json.perfis(@profiles.map { |profile| { id: profile.id.to_s, nome: profile.name } })
