# Segmentos na SPA (13, R252, R273, R295; decisão 0025): os segmentos de cada credor visível, com as condições no texto curto, a leitura por extenso,
# onde são usados e a situação; os filtros da página e o que a pessoa pode mudar em cada credor.
json.filtros do
  json.seleciona [ { id: "", nome: "Todos" }, { id: "contracts", nome: "Contratos" }, { id: "customers", nome: "Clientes" } ]
  json.uso [ { id: "", nome: "Todos" }, { id: "em_uso", nome: "Em uso" }, { id: "sem_uso", nome: "Sem uso" } ]
  json.situacao [ { id: "", nome: "Todas" }, { id: "ativos", nome: "Ativos" }, { id: "inativos", nome: "Desativados" } ]
end
json.credores(@tenants.map do |tenant|
  can_change = @can_change.include?(tenant.id)
  { id: tenant.id.to_s, nome: tenant.name, pode_mudar: can_change,
    segmentos: @segments.fetch(tenant.id, []).map do |segment|
      text = segment.text(result_names: @result_names)
      uses = segment.tiers.select(&:active)
      { id: segment.id.to_s, nome: segment.name, seleciona: t("segments.subjects.#{segment.subject}"),
        condicoes: text.lines.drop(1).map(&:short).join(" · "), leitura: text.long_text,
        uso: uses.any? ? "Enquadramento financeiro, item #{uses.map(&:position).join(', ')}" : "Sem uso", em_uso: uses.any?,
        ativo: segment.active?, situacao: segment.active? ? selo("Ativo", :success) : selo("Desativado", :neutral),
        alterado_em: datetime_br(segment.updated_at),
        mensagem_de_excluir: "O segmento \"#{segment.name}\" será excluído. Ele não está em uso, então nada muda na carteira." }
    end }
end)
