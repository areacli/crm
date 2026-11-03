# Enquadramento financeiro na SPA (13, R265 a R272, R276; 09, R160, R165, R180 a R182; 11, R207a, R246; decisão 0025): o credor da aba, os itens em ordem com
# as regras, o recálculo, os parâmetros e as políticas de encargos e os parâmetros dos acordos. Sem a permissão 14 no credor, os valores vêm só como texto
# e os parâmetros dos acordos não vêm.
tenant = @tenants.find { |candidate| candidate.id.to_s == params[:tenant_id].to_s } || @tenants.first
json.credor_id tenant&.id&.to_s
json.credores(@tenants.map { |candidate| { id: candidate.id.to_s, nome: candidate.name } })

if tenant
  setting = @settings.fetch(tenant.id)
  can_change = @can_change.include?(tenant.id)
  tiers = @tiers.fetch(tenant.id, []).select { |tier| tier.active? || tier.catch_all? }
  active = tiers.reject(&:catch_all?)
  run = @runs[tenant.id]
  json.pode_mudar can_change

  recalculation = if run&.failed?
    "O recálculo de #{datetime_br(run.started_at)} falhou#{" (#{run.error_kind})" if run.error_kind.present?}. A lista mostra os últimos itens calculados; o recálculo roda de novo amanhã às 5h30 ou ao confirmar uma carga."
  elsif run
    "Recalculado em #{datetime_br(run.started_at)} (#{number_br(run.processed)} contratos mudaram de item)."
  else
    "O recálculo ainda não rodou para este credor."
  end
  json.recalculo({ falhou: run&.failed? || false, texto: recalculation })

  json.itens(tiers.map do |tier|
    count, cents = @totals.fetch(tier.id, [ 0, 0 ])
    index = active.index(tier)
    reading = tier.segment.text unless tier.catch_all?
    { id: tier.id.to_s, ordem: tier.catch_all? ? "—" : (index + 1).to_s, nome: tier.name, trilha_padrao: tier.catch_all?,
      contratos: number_br(count), saldo: money(cents),
      regras: "Promessa até #{tier.promise_max_days} dias · acordo até #{tier.agreement_max_installments} parcelas",
      condicoes: (reading && "Condições: #{reading.lines.drop(1).map(&:short).join(" · ")}"),
      leitura: reading&.long_text,
      encargos: "Encargos: #{charge_rule_summary(tier, setting)}.",
      promessa_e_acordo: "Promessa: até #{tier.promise_max_days} dias. Acordo: até #{tier.agreement_max_installments} parcelas, entrada mínima de #{tier.agreement_min_down_payment_pct}%.",
      primeiro: index.nil? || index.zero?, ultimo: index.nil? || index == active.size - 1,
      segmento_url: (settings_segment_path(tier.segment) unless tier.catch_all?) }
  end)

  # Parâmetros de encargos do credor: o valor do campo (percentual com vírgula) e o texto de quem só vê.
  json.parametros({ charge_fine_pct: charge_field_value(setting, nil, :charge_fine_pct), charge_interest_pct: charge_field_value(setting, nil, :charge_interest_pct),
                    charge_index: setting.charge_index.to_s, charge_days_convention: setting.charge_days_convention.to_s, charge_fine_base: setting.charge_fine_base.to_s })
  json.parametros_texto({ charge_fine_pct: charge_pct(setting.charge_fine_pct), charge_interest_pct: charge_pct(setting.charge_interest_pct),
                          charge_index: charge_label(:index, setting.charge_index), charge_days_convention: charge_label(:days_convention, setting.charge_days_convention),
                          charge_fine_base: charge_label(:fine_base, setting.charge_fine_base) })

  # As cinco políticas de encargos, cada uma com o título, a ajuda, a escolha e as opções.
  json.politicas(TenantSetting::CHARGE_POLICIES.to_h do |policy|
    value = setting[policy].to_s
    [ policy, { titulo: t("charges.policies.#{policy}.title"), ajuda: t("charges.policies.#{policy}.help"), valor: value,
                texto: (value.present? ? t("charges.policies.#{policy}.#{value}") : ""),
                opcoes: TenantSetting.defined_enums.fetch(policy).keys.map { |option| { id: option, nome: t("charges.policies.#{policy}.#{option}") } } } ]
  end)

  inherit = { id: "", nome: "Herda do credor" }
  methods = Tier::INSTALLMENT_METHODS.map { |value| { id: value, nome: t("agreements.parameters.installment_methods.#{value}") } }
  conventions = Tier::DAYS_CONVENTIONS.map { |value| { id: value, nome: t("agreements.parameters.conventions.#{value}") } }
  fine_bases = Tier::FINE_BASES.map { |value| { id: value, nome: t("agreements.parameters.fine_bases.#{value}") } }
  json.opcoes({
    indices: Tier::INDEX_CODES.map { |value| { id: value, nome: charge_label(:index, value) } },
    convencoes: Tier::DAYS_CONVENTIONS.map { |value| { id: value, nome: charge_label(:days_convention, value) } },
    bases: Tier::FINE_BASES.map { |value| { id: value, nome: charge_label(:fine_base, value) } },
    metodos: methods, convencoes_acordo: conventions, bases_acordo: fine_bases,
    metodos_item: [ inherit ] + methods, convencoes_item: [ inherit ] + conventions, bases_item: [ inherit ] + fine_bases
  })

  # Parâmetros dos acordos (gravam sem conferência): só para quem pode mudar, como na página do servidor.
  if can_change
    json.acordo({ installment_rate_pct: charge_field_value(setting, nil, :installment_rate_pct), installment_method: setting.installment_method.to_s,
                  agreement_days_convention: setting.agreement_days_convention.to_s, agreement_fine_base: setting.agreement_fine_base.to_s })
    json.acordo_itens(tiers.map do |tier|
      { id: tier.id.to_s, nome: tier.name, installment_rate_pct: charge_field_value(tier, nil, :installment_rate_pct), installment_method: tier.installment_method.to_s,
        agreement_days_convention: tier.agreement_days_convention.to_s, agreement_fine_base: tier.agreement_fine_base.to_s }
    end)
  else
    json.acordo({})
    json.acordo_itens []
  end
else
  json.pode_mudar false
  json.itens []
end
