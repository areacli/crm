# Ficha do credenciamento na SPA (14, R307, R310; decisão 0025): situação, as ações de situação e as pessoas da operação com o vínculo neste credor.
accreditation = @accreditation
tons = { "active" => :success, "suspended" => :warning, "ended" => :neutral }
descricoes = { "suspended" => "Os usuários da operação perdem o acesso a #{accreditation.tenant.name} na hora; as distribuições continuam.",
               "ended" => "Os usuários perdem o acesso e as distribuições de #{accreditation.tenant.name} se encerram. Reativar não as traz de volta.",
               "active" => "Os usuários com vínculo voltam a ter acesso a #{accreditation.tenant.name}." }
json.id accreditation.id
json.nome @operation.short_name
json.subtitulo "#{@operation.legal_name} · CNPJ #{Document.format(@operation.cnpj)} · #{accreditation.tenant.name}"
json.credor accreditation.tenant.name
json.situacao selo(t("operations.statuses.#{accreditation.status}"), tons.fetch(accreditation.status))
json.motivo(accreditation.status_reason.presence && "Último motivo: #{accreditation.status_reason}")
json.motivo_tom(accreditation.active? ? "Information" : "Warning")
json.acoes((Accreditation.statuses.keys - [ accreditation.status ]).map { |status| { status: status, nome: t("operations.status_actions.#{status}"), descricao: descricoes.fetch(status), perigosa: status != "active" } })
json.pode_vincular policy(accreditation).link?
json.pessoas(@members.map do |member|
  membership = @memberships[member.user_id]
  { id: member.id, nome: member.user.name, email: member.user.email_address, na_operacao: member.active? ? (member.manager? ? "Gestor" : "Ativa") : "Desativada",
    vinculo: membership&.active? ? membership.profile.name : "Sem vínculo", ativa: member.active?, vinculo_id: (membership.id if membership&.active?), perfil_id: (membership.profile_id.to_s if membership&.active?) }
end)
