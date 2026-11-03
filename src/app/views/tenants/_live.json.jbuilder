# Credor no tempo real da SPA (decisão 0025): só o id, para as telas por credor (filas) se refazerem quando algo do credor muda.
json.array! registros do |tenant|
  json.id tenant.id
end
