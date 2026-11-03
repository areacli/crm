# Lote de distribuição no tempo real da SPA (decisão 0025): só o id; a página do lote se refaz quando a conferência ou a confirmação termina.
json.array! registros do |batch|
  json.id batch.id
end
