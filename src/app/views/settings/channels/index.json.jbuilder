# Métodos de recebimento na SPA (16, R373; decisão 0025): busca, filtro de credor e um método por linha; as integrações (12) no detalhe, só a quem tem a 14.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.pode_criar policy(PaymentChannel).new?
json.pode_criar_integracao policy(PaymentAccount).new?
json.linhas @channels do |channel|
  financial = @financial_tenant_ids.include?(channel.tenant_id)
  json.id channel.id
  json.codigo channel.code
  json.descricao channel.description
  json.credor channel.tenant.name
  json.credor_id channel.tenant_id
  json.tipo t("payments.channels.kinds.#{channel.kind}")
  json.integracoes(financial ? channel.payment_accounts.size.to_s : "—")
  json.webhook(channel.webhook_enabled? ? "Ativo" : "Sem segredo")
  json.situacao(channel.active? ? selo("Ativo", :success) : selo("Desativado", :neutral))
  json.editavel @editable_tenant_ids.include?(channel.tenant_id)
  json.financeiro financial
  json.contas(financial ? channel.payment_accounts.sort_by { |account| [ account.active? ? 0 : 1, account.modality, account.environment ] }.map do |account|
    { id: account.id, apelido: account.nickname, meio: t("payments.accounts.modalities.#{account.modality}"), fornecedor: provider_name(account.provider),
      ambiente: t("payments.accounts.environments.#{account.environment}"), certificado: account.certificate_expires_on ? "vence em #{date_br(account.certificate_expires_on)}" : "—",
      teste: account.last_test_status ? "#{account.last_test_status == "ok" ? "Boa" : "Falhou"}, #{datetime_br(account.last_tested_at)}" : "Nunca testada",
      situacao: account.active? ? selo("Ativa", :success) : selo("Desativada", :neutral) }
  end : [])
end
