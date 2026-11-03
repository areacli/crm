# Cliente no tempo real da SPA (decisão 0025): o que identifica o cliente para a tela que o mostra.
json.array! registros do |customer|
  json.id customer.id
  json.nome customer.name
  json.documento customer.masked_document
  json.credor customer.tenant.name
end
