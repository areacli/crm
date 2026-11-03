# Novo método de recebimento na SPA: os credores em que a pessoa tem a permissão 4 e os campos.
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.partial! "settings/channels/form", channel: @channel
