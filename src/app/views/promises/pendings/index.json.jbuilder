# Promessas pendentes na SPA (10, R192, R204; decisão 0025): as que a pessoa pode aprovar, com o filtro de credor.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.linhas @promises do |promise|
  json.id promise.id
  json.credor promise.tenant.name
  json.cliente promise.customer.name
  json.cliente_id promise.customer_id
  json.contrato promise.contract.label
  json.titulos promise_bill_numbers(promise)
  json.valor money(promise.total_cents)
  json.meio t("payments.methods.#{promise.payment_method}")
  json.data date_br(promise.promised_on)
  json.prazo "#{number_br(promise.days_asked)} dias"
  json.registrada_por(promise.user&.name || "—")
end
