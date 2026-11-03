# Lista de acordos na SPA (11, R243; decisão 0025): os filtros, os casos que pedem o gestor (na primeira página) e as linhas da página.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.com_origem @origins.present?
json.pode_ver_arquivo policy(AgreementExport).index?
json.filtros do
  json.situacoes(Agreement::STATES.map { |state| { id: state, nome: t("agreements.states.#{state}") } })
  json.operadores(@operators.map { |nome, id| { id: id.to_s, nome: nome } })
  json.origens(@origins.present? ? [ { id: "team", nome: "Equipe do credor" }, *@origins.map { |nome, id| { id: id.to_s, nome: nome } } ] : [])
  json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
end
json.casos(@cases || []) do |item|
  json.caso t("agreements.cases.#{item.kind}")
  json.acordo item.agreement&.number
  json.acordo_id item.agreement&.id
  json.cliente item.customer&.name
  json.cliente_id item.customer&.id
  json.credor item.tenant.name
  json.detalhe item.detail
  json.endereco item.link
end
json.linhas @agreements do |agreement|
  json.id agreement.id
  json.numero agreement.number
  json.cliente agreement.customer.name
  json.cliente_id agreement.customer_id
  json.credor agreement.tenant.name
  json.selos agreement_selos(agreement)
  json.forma agreement_mode(agreement)
  json.valor money(agreement.value_cents)
  json.desconto money(agreement.discount_cents)
  json.entrada money(agreement.down_payment_cents)
  json.parcelas number_br(agreement.installments_count)
  json.montou(agreement.user&.name || "—")
  json.origem origin_label(agreement)
  json.aprovou(agreement.decided_by&.name || "—")
  json.vale_ate date_br(agreement.valid_until)
end
