# O método de recebimento para o formulário (16, R373): tipos, os valores e se o código ainda muda.
json.tipos(PaymentChannel.kinds.keys.map { |kind| { id: kind, nome: t("payments.channels.kinds.#{kind}") } })
json.tipo channel.kind.to_s
json.codigo channel.code.to_s
json.descricao channel.description.to_s
json.codigo_travado channel.persisted? && channel.used?
