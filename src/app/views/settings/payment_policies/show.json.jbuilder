# Políticas de pagamento na SPA (R46, R46a, R62a, R64; 16; 11, R243; decisão 0025): por credor, as políticas de pagamento com as opções e as políticas de
# crédito, pagamento e tolerância dos acordos, com a última alteração de cada uma.
grupos = { "partial_payment_policy" => "Pagamento menor que o saldo", "withdrawn_payment_policy" => "Pagamento de título retirado",
           "withdrawn_reversal_policy" => "Título retirado, quitado e depois estornado", "reversal_month_policy" => "Mês em que o estorno desconta do valor recuperado",
           "instrument_reissue_policy" => "Instrumento cancelado porque o objeto mudou de valor ou de vencimento",
           "agreement_issue_all_policy" => "Emitir todas as parcelas de um acordo de uma vez" }
json.credores(@settings.map do |setting|
  tenant = setting.tenant
  politicas = Agreements::Policies.for(setting)
  historico = @agreement_history.fetch(tenant.id, [])
  { id: tenant.id, nome: tenant.name,
    pagamento: grupos.map do |campo, titulo|
      { campo: campo, titulo: titulo, valor: setting.public_send(campo),
        opcoes: TenantSetting.defined_enums.fetch(campo).keys.map { |valor| { id: valor, nome: t("payments.policies.#{campo}.#{valor}"), grupo: "#{campo}-#{tenant.id}", marcada: setting.public_send(campo) == valor } } }
    end,
    acordos: Agreements::Policies.keys(:payments).map do |chave|
      entry = Agreements::Policies.entry(chave)
      valor = politicas[chave]
      ultima = historico.find { |change| change.field == chave }
      politica = { chave: chave, titulo: t("agreements.policies.#{chave}.title"), ajuda: t("agreements.policies.#{chave}.help"), escolha: entry.kind == :choice,
                   ultima: ultima && "Última alteração: #{datetime_br(ultima.occurred_at)}, #{ultima.user&.name || "—"}: de #{ultima.before.presence || "—"} para #{ultima.after.presence || "—"}." }
      if entry.kind == :choice
        politica[:valor] = valor
        politica[:opcoes] = entry.options.map { |opcao| { id: opcao, nome: t("agreements.policies.#{chave}.options.#{opcao}"), grupo: "#{chave}-#{tenant.id}", marcada: valor == opcao } }
      else
        politica[:tipo] = valor["kind"]
        politica[:quantia] = policy_amount_field(valor)
        politica[:tipos] = entry.options.map { |opcao| { id: opcao, nome: t("agreements.policies.#{chave}.options.#{opcao}") } }
      end
      politica
    end }
end)
