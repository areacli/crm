# Divergências de valor na SPA (05, R99; decisão 0025): as abertas por padrão, o filtro de situação e de credor, a página e as linhas.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.vazio(@status == "open" ? "Nenhuma divergência aberta. Quando uma carga mudar o valor de um título com pagamento, ela aparece aqui." : "Nenhuma divergência encontrada.")
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.linhas @discrepancies do |item|
  json.id item.id
  json.titulo item.bill.number
  json.cliente item.bill.customer.name
  json.cliente_id(@view_customer_tenants.include?(item.tenant_id) ? item.bill.customer_id : nil)
  json.titulo_endereco(@view_customer_tenants.include?(item.tenant_id) ? bill_path(item.bill) : nil)
  json.credor item.tenant.name
  json.data date_br(item.created_at.to_date)
  json.anterior money(item.previous_cents)
  json.informado money(item.reported_cents)
  json.pago money(item.allocated_cents)
  json.saldo_antes money(item.balance_before_cents)
  json.saldo_depois money(item.balance_after_cents)
  json.efeito t("discrepancies.effects.#{item.effect}")
  json.selo(item.open? ? selo("Aberta", :warning) : selo("Tratada", :success))
  json.pode_tratar item.open? && policy(item).create?
end
