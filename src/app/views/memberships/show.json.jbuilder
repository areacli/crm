# Ficha do usuário na SPA (R36 a R42; decisão 0025): o acesso no credor, as ações que valem e o histórico de acessos e alterações.
membership = @membership
user = membership.user
proprio = user.id == Current.user.id
json.id membership.id
json.nome user.name
json.subtitulo "#{user.email_address} · #{membership.tenant.name}"
json.credor membership.tenant.name
json.partial! "memberships/selo", membership: membership
json.proprio proprio
json.ativo membership.active?
json.pode_editar_dados !proprio && membership.personal_data_editable?
json.acesso([ { rotulo: "Perfil", valor: membership.profile.name }, { rotulo: "Último acesso", valor: user.last_login_at ? datetime_br(user.last_login_at) : "Nunca entrou" } ] +
            (user.temporary_password? ? [ { rotulo: "Senha temporária até", valor: datetime_br(user.temporary_password_until) } ] : []))
nota = if proprio
  "Esta é a sua conta. Outra pessoa com a permissão de gerenciar usuários muda o seu perfil ou o seu acesso; a senha você troca em \"Trocar a senha\"."
elsif !membership.personal_data_editable?
  "Nome e senha são da pessoa, não do credor. Como ela atua em mais de um credor, só ela mesma e o administrador do sistema os alteram."
end
json.nota_do_acesso nota
json.historico(@events.map { |event| { quando: datetime_br(event.occurred_at), texto: event_description(event), quem: event.actor&.name || "—", endereco: event.ip_address || "—" } })
