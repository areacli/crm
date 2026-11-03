# Resultados de acionamento na SPA (R66, R67; decisão 0025): por credor em que a pessoa tem a permissão 9, os resultados na ordem do credor, com quantos
# acionamentos usam cada um; as opções do formulário (tipo e data de retorno) e os credores em que se pode criar.
json.varios_credores @several_tenants
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.tipos(ContactResult::KINDS.keys.map { |kind| { id: kind.to_s, nome: t("contacts.kinds.#{kind}") } })
json.retornos(ContactResult.return_rules.keys.map { |rule| { id: rule, nome: t("contacts.return_rules.#{rule}") } })
json.grupos(@tenants.map do |tenant|
  results = @results.fetch(tenant, [])
  { id: tenant.id, nome: tenant.name,
    resultados: results.each_with_index.map do |result, index|
      { id: result.id, nome: result.name, tipo_id: result.kind, tipo: t("contacts.kinds.#{result.kind}"),
        retorno_id: result.return_rule, retorno: t("contacts.return_rules.#{result.return_rule}"),
        invalida: result.invalidates_contact?, invalida_texto: result.invalidates_contact? ? "Sim" : "Não",
        admite_promessa: result.allows_promise?, admite_promessa_texto: result.allows_promise? ? "Sim" : "Não",
        acionamentos: number_br(@used.fetch(result.id, 0)), ativo: result.active?,
        situacao: result.active? ? selo("Ativo", :success) : selo("Desativado", :neutral),
        credor: tenant.name, primeiro: index.zero?, ultimo: index == results.size - 1 }
    end }
end)
