# Trilha das operações na SPA (14, R320, R325; decisão 0025): filtros e os registros da página.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.filtros do
  json.operacoes(@operations.map { |nome, id| { id: id.to_s, nome: nome } })
  json.usuarios(@users.map { |nome, id| { id: id.to_s, nome: nome } })
  json.tipos(OperationTrailEvent::KINDS.map { |kind| { id: kind, nome: t("operation_trails.kinds.#{kind}") } })
end
json.linhas @events do |event|
  json.id event.id
  json.quando datetime_br(event.created_at)
  json.operacao event.operation.short_name
  json.usuario event.user.name
  json.tipo t("operation_trails.kinds.#{event.kind}")
  json.cliente event.customer&.name
  json.cliente_id event.customer_id
  json.detalhe(event.customer ? event.customer.name : (event.query_text ? "“#{event.query_text}” (#{number_br(event.results.to_i)} resultados)" : "—"))
end
