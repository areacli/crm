# Texto dos encargos nas telas (09): a regra de um segmento numa linha (R177), os rótulos das opções, o percentual digitado e os valores em reais.
module ChargesHelper
  INDEX_LABELS = { "none" => "sem correção", "ipca" => "IPCA", "inpc" => "INPC", "igpm" => "IGP-M" }.freeze
  COMPONENT_LABELS = { "principal" => "Principal", "correction" => "Correção", "fine" => "Multa", "interest" => "Juros", "fees" => "Honorários" }.freeze

  # "multa 2% · juros 1% a.m. simples · IPCA · sem honorários" (R177), com o que o segmento herda do credor.
  def charge_rule_summary(segment, setting)
    rule = Charges::Rule.build(Charges::RuleSet.segment_values(segment), Charges::RuleSet.params_of(setting))
    interest = case rule.interest
    when "fixed" then "juros #{charge_pct(rule.rate * 100)} a.m. #{rule.form == 'simple' ? 'simples' : 'compostos'}"
    when "legal" then "juros pela taxa legal"
    else "sem juros"
    end
    [ "multa #{charge_pct(rule.fine * 100)}", interest, rule.index.presence&.upcase&.sub("IGPM", "IGP-M") || "sem correção",
      rule.fees.positive? ? "honorários #{charge_pct(rule.fees * 100)}" : "sem honorários" ].join(" · ")
  end

  # 2 → "2%", 2.5 → "2,5%", 0.3790 → "0,379%".
  def charge_pct(value)
    text = format("%.4f", value.to_f).sub(/0+\z/, "").sub(/\.\z/, "").tr(".", ",")
    "#{text}%"
  end

  # Valor de um campo percentual do formulário: o digitado (se houve erro) ou o gravado, com vírgula; vazio herda.
  def charge_field_value(segment, raw, column)
    return raw[column] if raw&.key?(column)

    value = segment[column]
    return "" if value.nil?

    format("%.4f", value.to_f).sub(/0+\z/, "").sub(/\.\z/, "").tr(".", ",")
  end

  def charge_choice(segment, raw, column) = raw&.key?(column) ? raw[column].to_s : segment[column].to_s

  def charge_label(group, value) = t("charges.#{group}.#{value}")

  def component_label(component) = COMPONENT_LABELS.fetch(component.to_s)

  TITLES = { "charge_fine_pct" => "Multa do credor", "charge_interest_pct" => "Juros do credor (ao mês)", "charge_index" => "Correção do credor",
             "charge_days_convention" => "Convenção de dias dos juros do credor", "charge_fine_base" => "Base da multa do credor" }.freeze

  def charge_field_title(name) = TITLES[name.to_s] || t("charges.policies.#{name}.title")

  def charge_value_text(name, value)
    case name.to_s
    when "charge_fine_pct", "charge_interest_pct" then charge_pct(value)
    when "charge_index" then charge_label(:index, value)
    when "charge_days_convention" then charge_label(:days_convention, value)
    when "charge_fine_base" then charge_label(:fine_base, value)
    else t("charges.policies.#{name}.#{value}")
    end
  end
end
