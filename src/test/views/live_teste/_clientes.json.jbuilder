# Visão de teste do tempo real (test/channels/live_channel_test.rb).
json.array! registros do |cliente|
  json.id cliente.id
  json.nome cliente.name
end
