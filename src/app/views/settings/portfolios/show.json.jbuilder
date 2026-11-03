# Configuração da carteira na SPA (R18, R20; 05, R104; 06, R117; decisão 0025): por credor, as faixas de atraso (com linhas livres para incluir), a prévia
# das salvas e as três políticas com o efeito de cada opção.
json.credores(@settings.map do |setting|
  tenant = setting.tenant
  linhas = setting.aging_brackets.map { |bracket| { de: bracket["from"].to_s, ate: bracket["to"].to_s, remover: false } }
  linhas += Array.new([ 7 - linhas.size, 2 ].max) { { de: "", ate: "", remover: false } }
  last_correction = Change.where(subject_type: "settings", subject_id: tenant.id, field: "correction_policy").includes(:user).order(occurred_at: :desc, id: :desc).first
  { id: tenant.id, nome: tenant.name, faixas: linhas, previa: Portfolio::AgingBrackets.from_stored(setting.aging_brackets).labels.map { |label| "#{label} dias" },
    pode_mudar_divergencia: Current.user.permitted?("change_financial_policies", tenant),
    divergencia: setting.discrepancy_policy,
    divergencias: TenantSetting.defined_enums.fetch("discrepancy_policy").keys.map do |value|
      { id: value, nome: t("discrepancies.policies.#{value}"), ajuda: t("discrepancies.policy_help.#{value}"), grupo: "divergencia-#{tenant.id}", marcada: setting.discrepancy_policy == value,
        pode_mudar: Current.user.permitted?("change_financial_policies", tenant) }
    end,
    correcao: setting.correction_policy,
    correcoes: TenantSetting.defined_enums.fetch("correction_policy").keys.map do |value|
      { id: value, nome: t("registry.correction_policies.#{value}"), ajuda: t("registry.correction_policy_help.#{value}"), grupo: "correcao-#{tenant.id}", marcada: setting.correction_policy == value }
    end,
    ultima_correcao: (last_correction && "Alterada por #{last_correction.user&.name || "sistema"} em #{datetime_br(last_correction.occurred_at)}."),
    a_vencer: setting.upcoming_display,
    opcoes_a_vencer: { "separate" => "Mostrar à parte do vencido", "summed" => "Somar ao vencido, mostrando o vencido em separado",
                       "detail_only" => "Só na ficha do cliente, fora dos totais" }.map { |id, nome| { id: id, nome: nome, grupo: "a-vencer-#{tenant.id}", marcada: setting.upcoming_display == id } } }
end)
