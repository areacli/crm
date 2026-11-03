# Lote de distribuição na SPA (14, R316; decisão 0025): as operações credenciadas, os segmentos, as exposições e, vindo da lista de clientes, o filtro.
json.credenciadas(@accreditations.map { |item| { id: item.id.to_s, nome: "#{item.operation.short_name} (#{item.tenant.name})" } })
json.segmentos(@segments.map { |segment| { id: segment.id.to_s, nome: "#{segment.name} (#{t("segments.subjects.#{segment.subject}")})" } })
json.exposicoes(Distribution::EXPOSURES.map { |exposure| { id: exposure, nome: t("distributions.exposures.#{exposure}") } })
json.selecao @selection
