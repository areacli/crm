# Regras do item do enquadramento financeiro na SPA (13, R294; 09, R160, R177; 10, R189): encargos e prazo da promessa; o campo vazio herda o parâmetro do credor.
setting = @tenant.setting
json.id @tier.id.to_s
json.nome @tier.name
json.credor_id @tenant.id.to_s
json.ajuda "Campo vazio usa o parâmetro do credor (multa #{charge_pct(setting.charge_fine_pct)}, juros #{charge_pct(setting.charge_interest_pct)} ao mês, #{charge_label(:index, setting.charge_index)}). Mudar a regra passa pela conferência do impacto."
json.valores({ fine_pct: charge_field_value(@tier, nil, :fine_pct), interest_kind: @tier.interest_kind.to_s, interest_pct: charge_field_value(@tier, nil, :interest_pct),
               interest_form: @tier.interest_form.to_s, index_code: @tier.index_code.to_s, fees_pct: charge_field_value(@tier, nil, :fees_pct),
               fees_in_contract: @tier.fees_in_contract?, days_convention: @tier.days_convention.to_s, fine_base: @tier.fine_base.to_s,
               promise_max_days: @tier.promise_max_days.to_s })
json.opcoes({
  juros: Tier::INTEREST_KINDS.map { |value| { id: value, nome: charge_label(:interest_kind, value) } },
  formas: Tier::INTEREST_FORMS.map { |value| { id: value, nome: charge_label(:interest_form, value) } },
  indices: [ { id: "", nome: "Usar a do credor (#{charge_label(:index, setting.charge_index)})" } ] + Tier::INDEX_CODES.map { |value| { id: value, nome: charge_label(:index, value) } },
  convencoes: [ { id: "", nome: "Usar a do credor (#{charge_label(:days_convention, setting.charge_days_convention)})" } ] +
              Tier::DAYS_CONVENTIONS.map { |value| { id: value, nome: charge_label(:days_convention, value) } },
  bases: [ { id: "", nome: "Usar a do credor (#{charge_label(:fine_base, setting.charge_fine_base)})" } ] + Tier::FINE_BASES.map { |value| { id: value, nome: charge_label(:fine_base, value) } }
})
