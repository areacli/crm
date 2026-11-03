# Perfis disponíveis para operações no credor do credenciamento, para o vínculo de uma pessoa (14, R310).
json.nome @member.user.name
json.perfis(@profiles.map { |profile| { id: profile.id.to_s, nome: profile.name } })
