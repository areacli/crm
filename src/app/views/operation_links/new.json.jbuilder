# Credores em que o gestor da operação pode dar vínculo, cada um com os perfis disponíveis para operações (14, R310).
json.nome @member.user.name
json.credores(@accreditations.map do |accreditation|
  { id: accreditation.id.to_s, nome: accreditation.tenant.name, perfis: accreditation.tenant.profiles.select(&:available_to_operations?).map { |profile| { id: profile.id.to_s, nome: profile.name } } }
end)
