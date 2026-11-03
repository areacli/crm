# Acordos pendentes na SPA (11, R216, R243; decisão 0025): as propostas que a pessoa pode aprovar, com o filtro de credor.
json.varios_credores @several_tenants
json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
json.linhas @agreements do |agreement|
  json.id agreement.id
  json.credor agreement.tenant.name
  json.numero agreement.number
  json.cliente agreement.customer.name
  json.cliente_id agreement.customer_id
  json.valor money(agreement.value_cents)
  json.desconto money(agreement.discount_cents)
  json.desconto_por_componente discounts_text(agreement.discounts)
  json.parcelas number_br(agreement.installments_count)
  json.montou(agreement.user&.name || "—")
  json.vale_ate date_br(agreement.valid_until)
end
