# Lista de acionamentos na SPA (R78; decisão 0025): o período (padrão, os últimos 7 dias; até 92), os filtros, a página e as linhas.
json.de @from.iso8601
json.ate @to.iso8601
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.com_origem @origins.present?
json.filtros do
  json.operadores(@operators.map { |nome, id| { id: id.to_s, nome: nome } })
  json.canais(ContactAttempt::CHANNELS.map { |canal| { id: canal, nome: t("contacts.channels.#{canal}") } })
  json.resultados(@result_options.map { |nome, id| { id: id.to_s, nome: nome } })
  json.tipos(ContactResult::KINDS.keys.map { |tipo| { id: tipo.to_s, nome: t("contacts.kinds.#{tipo}") } })
  json.origens(@origins.present? ? [ { id: "team", nome: "Equipe do credor" }, *@origins.map { |nome, id| { id: id.to_s, nome: nome } } ] : [])
  json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
end
json.linhas @attempts do |attempt|
  json.id attempt.id
  json.quando datetime_br(attempt.contacted_at)
  json.cliente attempt.customer.name
  json.cliente_id attempt.customer_id
  json.credor attempt.tenant.name
  json.canal t("contacts.channels.#{attempt.channel}")
  json.resultado attempt.result.name
  json.tipo t("contacts.kinds.#{attempt.result_kind}")
  json.operador(attempt.summary_only_for_viewer? ? "Outra origem" : (attempt.user&.name || "—"))
  json.origem origin_label(attempt)
  json.retorno(attempt.return_at ? datetime_br(attempt.return_at) : "—")
  json.detalhe(attempt.contract ? "Contrato #{attempt.contract.label}." : nil)
end
