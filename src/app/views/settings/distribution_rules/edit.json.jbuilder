# Escolhas do formulário do item do enquadramento da distribuição na SPA (14, R342): segmentos livres, operações credenciadas, exposições e posições.
json.segmentos(@segments.map { |segment| { id: segment.id.to_s, nome: segment.name } })
json.operacoes(@accredited.map { |operation| { id: operation.id.to_s, nome: operation.short_name } })
json.exclusiva @tenant.setting.operation_exclusive
json.exposicoes(Distribution::EXPOSURES.map { |exposure| { id: exposure, nome: t("distributions.exposures.#{exposure}") } })
json.posicoes(@current.each_with_index.map { |item, index| { id: index.to_s, nome: "Antes de #{item.segment.name}" } } + [ { id: @current.size.to_s, nome: "No fim" } ])
json.item(@item && { segmento: @segment.name, operacoes: @item.operation_ids.map(&:to_s), exposicao: @item.exposure })
