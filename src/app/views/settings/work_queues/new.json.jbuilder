# Escolhas do formulário de item do enquadramento das filas na SPA (15, R349): os segmentos livres do sujeito e as posições.
json.segmentos(@segments.map { |segment| { id: segment.id.to_s, nome: segment.name } })
json.posicoes(@current.each_with_index.map { |item, index| { id: index.to_s, nome: "Antes de #{item.name}" } } + [ { id: @current.size.to_s, nome: "No fim" } ])
json.item(@item && { nome: @item.name, segmento_id: @item.segment_id.to_s, entrega: @item.delivers })
