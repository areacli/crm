# Importação no tempo real da SPA (decisão 0025): a situação e o andamento, para a lista e a página da importação.
json.array! registros do |import|
  json.id import.id
  json.partial! "imports/selo", import: import
end
