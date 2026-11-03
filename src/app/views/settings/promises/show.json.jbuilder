# Promessas e acordos na SPA (10, R189, R190, R206; 11, R207, R209, R243, R246, T6; decisão 0025): por credor em que a pessoa tem a permissão 14, as
# políticas das promessas, o prazo máximo de cada item do enquadramento com a alçada de cada perfil, as políticas, variáveis e limites dos acordos e as
# alterações recentes. Os números saem como texto, do jeito que voltam no envio (vírgula nos valores em reais).
componentes = Agreements::Caps::COMPONENTS.reverse
# Um campo do formulário de um bloco: `chave` é o nome no envio (com ponto, aninhado: "caps.cash.interest"); `par`, o segundo campo da mesma linha (o teto à vista
# ao lado do parcelado). `rotulo` é o nome acessível do campo.
campo = ->(rotulo, chave, valor, par: nil, ajuda: nil, obrigatorio: true) { { rotulo: rotulo, chave: chave, valor: valor.to_s, par: par, ajuda: ajuda, obrigatorio: obrigatorio } }
# Os tetos de desconto (ou limites) por componente, parcelado e à vista na mesma linha.
tetos = lambda do |caps, rotulo, onde|
  componentes.map do |component|
    nome = component_name(component)
    campo.("#{nome}: parcelado e à vista (%)", "caps.installment.#{component}", Agreements::Caps.get(caps, "installment", component),
           par: { chave: "caps.cash.#{component}", valor: Agreements::Caps.get(caps, "cash", component).to_s,
                  rotulo: "#{rotulo} em #{nome.downcase}, #{t("agreements.modes.cash").downcase}, #{onde}" })
      .merge(rotulo_acessivel: "#{rotulo} em #{nome.downcase}, #{t("agreements.modes.installment").downcase}, #{onde}")
  end
end
quem = ->(change) { change.user&.name || "—" }
de_para = ->(change) { "de #{change.before.presence || "—"} para #{change.after.presence || "—"}" }

json.credores(@tenants.map do |tenant|
  setting = tenant.setting
  tiers = @tiers.fetch(tenant.id, [])
  profiles = @profiles.fetch(tenant.id, [])
  policies = Agreements::Policies.for(setting)
  agreement_history = @agreement_history.fetch(tenant.id, [])

  { id: tenant.id, nome: tenant.name,
    # Políticas das promessas (uma lista de escolha por política; as opções já dizem o efeito).
    promessa: { tolerancia: setting.promise_tolerance_days.to_s, carencia: setting.promise_grace_days.to_s, minimo: setting.promise_min_paid_pct.to_s,
                contam: setting.promise_counting, depois_da_quebra: setting.promise_after_break, parcial: setting.promise_partial },
    opcoes_contam: TenantSetting::PROMISE_COUNTING.map { |value| { id: value, nome: t("promises.policies.counting.#{value}") } },
    opcoes_depois_da_quebra: TenantSetting::PROMISE_AFTER_BREAK.map { |value| { id: value, nome: t("promises.policies.after_break.#{value}") } },
    opcoes_parcial: TenantSetting::PROMISE_PARTIAL.map { |value| { id: value, nome: t("promises.policies.partial.#{value}") } },

    # Prazo máximo do item e alçada de cada perfil.
    perfis: profiles.map { |profile| { id: profile.id, nome: profile.name } },
    alcadas: tiers.map do |tier|
      { id: tier.id, nome: tier.name,
        campos: [ campo.("Prazo máximo (dias)", "max_days", tier.promise_max_days).merge(rotulo_acessivel: "Prazo máximo de #{tier.name} em dias") ] +
                profiles.map { |profile| campo.("Alçada: #{profile.name} (dias)", "limits.#{profile.id}", @limits.dig(tier.id, profile.id)&.max_days).merge(rotulo_acessivel: "Alçada de #{profile.name} em #{tier.name}, em dias") } }
    end,

    # Políticas dos acordos da aba "Promessas e acordos": escolha (lista) ou valor (em reais, percentual ou igual à tolerância).
    politicas_de_acordo: Agreements::Policies.keys(:agreements).map do |key|
      entry = Agreements::Policies.entry(key)
      changes = agreement_history.select { |change| change.field == key }.first(10)
      value = policies[key]
      { chave: key, de_escolha: entry.kind == :choice, titulo: t("agreements.policies.#{key}.title"), ajuda: t("agreements.policies.#{key}.help"),
        opcoes: entry.options.map { |option| { id: option, nome: t("agreements.policies.#{key}.options.#{option}") } },
        escolha: entry.kind == :choice ? value : value["kind"], quantia: (policy_amount_field(value) unless entry.kind == :choice),
        rotulo_quantia: "#{t("agreements.policies.#{key}.title")}: valor (reais ou percentual)",
        ultima: (changes.any? ? "Última alteração: #{datetime_br(changes.first.occurred_at)}, #{quem.(changes.first)}: #{de_para.(changes.first)}." : nil),
        historico: changes.map { |change| "#{datetime_br(change.occurred_at)}, #{quem.(change)}: #{de_para.(change)}." }.join(" ") }
    end,

    # Variáveis de acordo de cada item (passam pela conferência do impacto).
    variaveis: tiers.map do |tier|
      { id: tier.id, nome: tier.name,
        resumo: "#{tier.name}: até #{tier.agreement_max_installments} parcelas, parcela mínima de #{money(tier.agreement_min_installment_cents)}, entrada de #{tier.agreement_min_down_payment_pct}%",
        campos: tetos.(tier.agreement_caps, "Teto de desconto", "em #{tier.name}") + [
          campo.("Número máximo de parcelas", "max_installments", tier.agreement_max_installments),
          campo.("Parcela mínima (R$)", "min_installment", Money.format(tier.agreement_min_installment_cents)),
          campo.("Entrada mínima (% do valor líquido)", "min_down_payment_pct", tier.agreement_min_down_payment_pct),
          campo.("Prazo da entrada (dias)", "down_payment_days", tier.agreement_down_payment_days),
          campo.("Validade da proposta (dias)", "validity_days", tier.agreement_validity_days),
          campo.("Tolerância de atraso (dias)", "tolerance_days", tier.agreement_tolerance_days),
          campo.("Quebra por atraso de parcela (dias)", "break_days", tier.agreement_break_days)
        ] }
    end,

    # Limites de cada perfil em cada item (um bloco por par).
    limites: tiers.flat_map do |tier|
      profiles.map do |profile|
        limit = AgreementLimit.for(profile, tier)
        { item_id: tier.id, perfil_id: profile.id,
          resumo: "#{profile.name} em #{tier.name}: até #{limit.max_installments} parcelas, entrada de #{limit.min_down_payment_pct}%#{", valor líquido até #{money(limit.ceiling_value_cents)}" if limit.ceiling_value_cents}",
          campos: tetos.(limit.caps, "Limite de desconto", "de #{profile.name} em #{tier.name}") + [
            campo.("Parcelas até", "max_installments", limit.max_installments),
            campo.("Entrada mínima (%)", "min_down_payment_pct", limit.min_down_payment_pct),
            campo.("Teto do desconto total (R$)", "ceiling_discount", (Money.format(limit.ceiling_discount_cents) if limit.ceiling_discount_cents), obrigatorio: false, ajuda: "Opcional; vazio, sem teto."),
            campo.("Teto do valor líquido do acordo (R$)", "ceiling_value", (Money.format(limit.ceiling_value_cents) if limit.ceiling_value_cents), obrigatorio: false, ajuda: "Opcional; vazio, sem teto.")
          ] }
      end
    end,

    # Alterações recentes (as 20 últimas), com o que mudou já escrito.
    historico: @history.fetch(tenant.id, []).first(20).map do |entry|
      perfil = -> { @profile_names[entry.field.to_s.delete_prefix("profile:").to_i]&.name }
      item = @tier_names[entry.subject_id]&.name
      o_que = case entry.subject_type
      when "promise_limit" then "#{item}: #{entry.field == "max_days" ? "prazo máximo" : "alçada de #{perfil.()}"}"
      when "agreement_limit" then "Acordos, limite de #{perfil.()} em #{item}"
      when "agreement_tier" then "Acordos, #{item}: #{t("agreements.history_fields.#{entry.field}", default: entry.field)}"
      when "agreement_settings" then "Acordos: #{t("agreements.policies.#{entry.field}.title", default: t("agreements.history_fields.#{entry.field}", default: entry.field))}"
      else t("promises.policies.fields.#{entry.field}", default: entry.field)
      end
      { id: entry.id, quando: datetime_br(entry.occurred_at), quem: quem.(entry), o_que: o_que, antes: entry.before.presence || "—", depois: entry.after.presence || "—" }
    end }
end)
