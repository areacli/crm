# Página do acordo na SPA (11, R216 a R239; decisão 0025): situação, avisos, títulos e base, entrada e parcelas, títulos de acordo e de estorno,
# histórico, condições, aceite e quitações, e as ações que a pessoa pode fazer. Os mesmos textos da página do servidor.
agreement = @agreement
policy = policy(agreement)
estado_do_titulo = lambda do |bill|
  case bill.status
  when "paid" then selo("Pago", :success)
  when "canceled" then selo("Cancelado", :neutral)
  when "scheduled" then selo("Aguardando efetivação", :info)
  when "active" then bill.due_date < Date.current ? selo("Vencido", :danger) : selo("A vencer", :info)
  else selo(t("agreements.bill_states.#{bill.status}", default: bill.status), :neutral)
  end
end

json.id agreement.id
json.numero agreement.number
json.cliente agreement.customer.name
json.cliente_id agreement.customer_id
json.credor agreement.tenant.name
json.selos agreement_selos(agreement)
termo_ok = @term["missing"].blank?
json.pode do
  json.termo policy.term? && !agreement.state_pending? && termo_ok && !agreement.state_refused?
  json.aceitar policy.accept? && termo_ok
  json.aprovar policy.approve?
  json.recusar policy.approve?
  json.cancelar policy.cancel?
  json.quitar policy.settle?
  json.quebrar policy.break?
  json.reverter policy.revert?
  json.concluir policy.conclude?
end
avisos = []
if agreement.state_pending?
  avisos << selo("Esta proposta passou dos limites de quem a montou. Só quem tem os limites que a cobririam, e não a montou, pode aprová-la; ela vale até #{date_br(agreement.valid_until)}.", :warning)
elsif agreement.state_approved?
  avisos << selo("Proposta aprovada. Apresente o termo ao cliente e registre o aceite até #{date_br(agreement.valid_until)}.", :info)
elsif agreement.reason.present?
  avisos << selo("Motivo: #{agreement.reason}", :info)
end
avisos << selo("O termo não pode ser gerado: faltam dados do credor (#{@term['missing'].to_sentence}). Complete o cadastro do credor para registrar o aceite.", :danger) if !termo_ok && agreement.proposal?
avisos << selo("Em reversão desde #{datetime_br(agreement.reversing_since)}: #{agreement.reversal_reason}. A tarefa diária não quebra o acordo, os encargos e a contagem dos prazos ficam parados, e o crédito aguardando alocação do contrato não se aloca nem se transfere até concluir ou desistir.", :danger) if agreement.reversing?
agreement.terms["warnings"].to_a.each { |text| avisos << selo(text, :warning) }
if agreement.state_awaiting_effectuation?
  entry_title = @titles.find { |bill| bill.composition["number"].to_i.zero? }
  avisos << selo("Aguardando efetivação. O acordo vira ativo quando a entrada #{entry_title&.number} for paga (o credor emite a cobrança). Os títulos originais seguem em cobrança até lá; a entrada vence em #{date_br(agreement.down_payment_due)}.", :info)
elsif agreement.state_broken?
  efeito = agreement.break_kind == "before_effectuation" ? "Os títulos originais voltaram a ser cobrados." : (agreement.break_form == "single_title" ? "O título da quebra reúne o que faltava pagar." : "Os títulos de acordo seguem em cobrança, cada um com o vencimento dele.")
  avisos << selo("Acordo quebrado em #{datetime_br(agreement.broken_at)}: #{agreement.reason}. #{efeito}", :danger)
elsif agreement.state_canceled? && agreement.accepted_at
  avisos << selo("Acordo cancelado: #{agreement.reason}. Os títulos originais voltaram a ser cobrados.", :info)
end
json.avisos avisos

columns = component_columns(agreement.agreement_bills.map(&:base))
json.titulos do
  json.colunas([ { texto: "Título", numero: false }, { texto: "Contrato", numero: false }, *columns.map { |component| { texto: component_name(component), numero: true } },
                 { texto: "Base", numero: true }, { texto: "Desconto", numero: true }, { texto: "No acordo", numero: true } ])
  json.linhas(agreement.agreement_bills.sort_by { |item| [ item.bill.due_date, item.bill_id ] }.map do |item|
    { celulas: [ item.bill.number, item.contract.label, *columns.map { |component| money(item.base.fetch(component, 0)) }, money(item.base_total_cents), money(item.discount_total_cents), money(item.value_cents) ] }
  end)
end
json.parcelas(agreement.schedule.map do |row|
  { titulo: row["number"].to_i.zero? ? "Entrada" : "Parcela #{row['number']}", vencimento: date_br(Date.iso8601(row["due"])), valor: money(row["amount_cents"]),
    juros: money(row["interest_cents"]), amortizacao: money(row["amortization_cents"]), falta: money(row["balance_cents"]) }
end)
json.ajuda_dos_titulos_de_acordo "Existem desde o aceite e entram na cobrança com a efetivação#{agreement.effectuated? ? " (efetivado em #{date_br(agreement.effectuated_at.to_date)} #{t("agreements.effectuated_by.#{agreement.effectuated_by}")})" : ""}. O devido de hoje tem a mora dos parâmetros congelados no acordo e os juros do parcelamento já corridos."
json.titulos_de_acordo(@titles.map do |bill|
  due = @ledgers[bill.id]&.due(Date.current)
  { numero: "#{bill.number}#{" (título da quebra)" if bill.kind_break?}", endereco: bill_path(bill), vencimento: date_br(bill.due_date), valor: money(bill.amount_cents), pago: money(bill.paid_cents),
    mora: due ? money(due.late) : "—", devido: due && !bill.paid? ? money(due.total) : "—", selo: estado_do_titulo.(bill) }
end)
json.titulos_de_estorno((@reversal_titles || []).map do |bill|
  { numero: bill.number, endereco: bill_path(bill), vencimento: date_br(bill.due_date), valor: money(bill.amount_cents), pago: money(bill.paid_cents), selo: estado_do_titulo.(bill) }
end)
json.historico(@events.map { |event| { quando: datetime_br(event.occurred_at), evento: "#{t("agreements.events.#{event.kind}")}#{" — #{event.data['reason']}" if event.data["reason"].present?}", quem: event.user&.name || "Sistema" } })
condicoes = [ [ "Forma", agreement_mode(agreement) ], [ "Enquadramento", agreement.terms.dig("tier", "name") ], [ "Base", money(agreement.base_cents) ],
              [ "Desconto", "#{money(agreement.discount_cents)} (#{discounts_text(agreement.discounts)})" ], [ "Valor do acordo", money(agreement.value_cents) ] ]
condicoes << [ "Crédito usado", "#{money(agreement.credit_cents + agreement.credit_down_cents)} como #{agreement.credit_cents.positive? ? "abatimento do valor" : "pagamento da entrada"}" ] if agreement.credit_cents.positive? || agreement.credit_down_cents.positive?
condicoes << [ "Valor líquido", money(agreement.net_cents) ]
if agreement.installments_count.positive?
  condicoes << [ "Método", "#{t("agreements.methods.#{agreement.installment_method}")}#{" a #{percent_decimal(agreement.rate_pct)} ao mês" unless agreement.installment_method == "none"}" ]
  condicoes << [ "Taxa efetiva anual", percent_decimal(agreement.effective_annual_pct) ]
  condicoes << [ "Juros do parcelamento", money(agreement.interest_cents) ]
end
condicoes << [ "Total a pagar", money(agreement.total_cents) ]
condicoes << [ "Montada por", "#{agreement.user&.name || "—"} em #{date_br(agreement.built_on)}" ]
condicoes << [ "Aprovada por", agreement.decided_by ? "#{agreement.decided_by.name} em #{datetime_br(agreement.decided_at)}" : "—" ]
condicoes << [ "Vale até", date_br(agreement.valid_until) ] unless agreement.accepted_at
json.condicoes(condicoes.map { |rotulo, valor| { rotulo: rotulo, valor: valor } })
json.aceite(agreement.accepted_at ? [ [ "Aceito por", "#{agreement.accepted_by_customer&.name}, #{t("agreements.roles.#{agreement.accepted_role}")}" ],
                                      [ "Aceite", "#{channel_name(agreement.accepted_channel)}, #{datetime_br(agreement.accepted_at)}" ],
                                      [ "Termo apresentado", "#{channel_name(agreement.presented_channel)}, #{datetime_br(agreement.presented_at)}" ],
                                      [ "Comprovante", agreement.proof.presence || "—" ],
                                      [ "Registrado por", "#{agreement.registered_by&.name} em #{datetime_br(agreement.registered_at)}" ] ].map { |rotulo, valor| { rotulo: rotulo, valor: valor } } : [])
json.quitacoes(policy.settle? ? @settlements.map { |settlement| "Quitação calculada para #{date_br(settlement.on_date)}: #{money(settlement.amount_cents)}, válida até essa data." } : [])
