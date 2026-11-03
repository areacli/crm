# Enquadramento da distribuição na SPA (14, R342 a R347; decisão 0025): os itens em ordem, com as condições do segmento, e a trilha padrão no fim.
json.credor_id @tenant.id.to_s
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.itens(@items.each_with_index.map do |item, index|
  { indice: index, ordem: (index + 1).to_s, segmento: item.segment.name, operacoes: item.operation_ids.map { @operations[_1] }.compact.join(", "),
    exposicao: t("distributions.exposures.#{item.exposure}"), contratos: number_br(@counts[item.id].to_i), primeiro: index.zero?, ultimo: index == @items.size - 1,
    detalhe: "Condições: #{item.segment.text.short_text.lines.drop(1).map(&:strip).join(" · ")}" }
end)
