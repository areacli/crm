# Página do método de recebimento na SPA (16, R373; R45): os dados, o webhook (endereço, formato e se há segredo) e se pode ser excluído.
channel = @channel
json.id channel.id
json.nome "Método #{channel.code_was || channel.code}"
json.credor channel.tenant.name
json.partial! "settings/channels/form", channel: channel
json.ativo channel.active?
json.pode_excluir !channel.used?
json.webhook do
  json.endereco payments_webhook_url(channel)
  json.formato channel.webhook_adapter
  json.segredo(channel.webhook_enabled? ? "Definido (não é mostrado de novo)" : "Ainda não gerado")
end
