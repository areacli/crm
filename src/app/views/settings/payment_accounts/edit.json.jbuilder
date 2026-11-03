# Página da integração na SPA (12, R259 a R269): dados, campos do manifesto, conexão, as ações que valem e o histórico.
account = @account
disponivel = account.provider_available?
com_webhook = disponivel && account.manifest.field("webhook_secret").present?
json.id account.id
json.nome "Integração #{account.nickname_was || account.nickname}"
json.subtitulo "#{account.tenant.name} · #{t("payments.accounts.modalities.#{account.modality}")} em #{provider_name(account.provider)} · #{t("payments.accounts.environments.#{account.environment}")}"
json.situacao(account.active? ? selo("Ativa", :success) : selo("Desativada", :neutral))
json.ativa account.active?
json.disponivel disponivel
json.com_webhook com_webhook
json.pode_excluir !account.used?
json.apelido account.nickname.to_s
json.metodo_id account.channel_id.to_s
json.metodos(PaymentChannel.where(tenant_id: account.tenant_id).order(:code).map { |channel| { id: channel.id.to_s, nome: "#{channel.code} · #{channel.description}" } })
if disponivel
  json.partial! "settings/payment_accounts/campos", account: account
else
  json.campos []
end
json.conexao([ { rotulo: "Último teste", valor: account.last_test_status ? "#{account.last_test_status == "ok" ? "Boa" : "Falhou"}, #{datetime_br(account.last_tested_at)}. #{account.last_test_message}" : "Nunca testada" } ] +
             (com_webhook ? [ { rotulo: "Segredo do webhook", valor: account.secret_set?("webhook_secret") ? "Definido (não é mostrado de novo)" : "Ainda não gerado" } ] : []))
json.historico(@history.map do |change|
  { quando: datetime_br(change.occurred_at), quem: change.user&.name || "—", ato: t("payments.accounts.history.#{change.event}", default: change.event),
    campo: account_field_label(account, change.field), antes: change.before.presence || "—", depois: change.after.presence || change.note.presence || "—" }
end)
