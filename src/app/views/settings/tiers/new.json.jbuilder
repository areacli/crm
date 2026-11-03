# Escolhas do formulário "Incluir segmento" na SPA (13, R293, SG15): os segmentos de contratos ainda fora do enquadramento, a posição e o item de onde copiar as regras.
json.credor_id @tenant.id.to_s
json.segmentos(@candidates.map { |segment| { id: segment.id.to_s, nome: "#{segment.name} — #{segment.text.lines.drop(1).map(&:short).join(' · ')}" } })
json.segmentos_de_clientes @customer_segments.positive?
json.posicoes(@items.reject(&:catch_all?).map { |tier| { id: tier.id.to_s, nome: "Antes de #{tier.name}" } } + [ { id: "", nome: "Antes de Demais (no fim)" } ])
json.copiar_de(@items.map { |tier| { id: tier.id.to_s, nome: tier.name } })
json.copiar_padrao @items.find(&:catch_all?)&.id&.to_s
