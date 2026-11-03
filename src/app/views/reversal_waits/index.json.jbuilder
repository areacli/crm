# Estornos à espera do gestor na SPA (11, R233, AH2; decisão 0025): os que esperam, com as decisões possíveis de cada um, e os decididos há pouco.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.esperando @waits do |wait|
  json.id wait.id
  json.pagamento wait.payment.identifier
  json.valor money(wait.amount_cents)
  json.credor wait.tenant.name
  json.motivo t("reversal_waits.reasons.#{wait.reason}")
  json.espera "#{wait.waiting_days} dia(s)"
  json.acordo wait.agreement&.number
  json.acordo_id wait.agreement&.id
  json.cliente wait.agreement&.customer&.name
  json.cliente_id wait.agreement&.customer_id
  json.contrato wait.contract.label
  json.detalhe "Estorno de #{date_br(wait.reversed_on)}, processado em #{date_br(wait.processed_on)}."
  json.escolhas(@options.fetch(wait.id).map { |choice| { id: choice, nome: t("reversal_waits.choices.#{choice}") } })
end
json.decididos @decided do |wait|
  json.quando datetime_br(wait.decided_at)
  json.acordo wait.agreement&.number
  json.acordo_id wait.agreement&.id
  json.valor money(wait.amount_cents)
  json.decisao t("reversal_waits.choices.#{wait.decision}")
  json.quem(wait.decided_by&.name || "—")
  json.motivo wait.note
end
