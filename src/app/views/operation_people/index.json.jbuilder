# Pessoas da operação na SPA (14, R310, R310a, R327; decisão 0025): as pessoas, a situação, os vínculos por credor e as ações de cada uma.
json.operacao @operation.short_name
json.pode_vincular @linkable.any?
json.linhas @members do |member|
  json.id member.id
  json.nome "#{member.user.name}#{" (você)" if member.user_id == Current.user.id}"
  json.nome_da_pessoa member.user.name
  json.email member.user.email_address
  json.situacao(member.active? ? selo(member.manager? ? "Gestor" : "Ativa", :success) : selo("Desativada", :neutral))
  json.vinculos(Array(@memberships[member.user_id]).map { |membership| "#{membership.tenant.name} · #{membership.profile.name}" }.join("; ").presence || "Sem vínculo")
  json.propria member.user_id == Current.user.id
  json.ativa member.active?
  json.gestor member.manager?
end
