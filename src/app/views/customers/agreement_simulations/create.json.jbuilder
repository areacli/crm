# Resultado da simulação na SPA (11, R211 a R216): o problema (com o campo) ou a base e os descontos por título, os totais e a tabela de parcelas.
json.problema @problem
json.campo @field
quote = @quote
if quote
  avisos = quote.warnings.map { |text| selo(text, :warning) }
  conclusao = if quote.error then selo("Esta proposta não pode ser criada: #{quote.error}", :danger)
  elsif quote.pending? then selo("Fora dos seus limites: a proposta nasce pendente de aprovação, e quem pode aprová-la é quem tem os limites que a cobririam. Item para negociar: #{quote.tier.name}.", :warning)
  else selo("Dentro dos seus limites: a proposta nasce aprovada. Item para negociar: #{quote.tier.name}.", :info)
  end
  avisos << conclusao
  json.avisos avisos
  json.desconto discounts_text(quote.discounts)
  columns = component_columns(quote.rows.map(&:base))
  json.base do
    json.colunas([ { texto: "Título", numero: false }, *columns.map { |component| { texto: component_name(component), numero: true } }, { texto: "Base", numero: true }, { texto: "Desconto", numero: true }, { texto: "No acordo", numero: true } ])
    json.linhas([ *quote.rows.map { |row| { celulas: [ row.bill.number, *columns.map { |component| money(row.base.fetch(component, 0)) }, money(row.base_total), money(row.discount_total), money(row.value) ] } },
                  { celulas: [ "Total", *columns.map { |component| money(quote.rows.sum { |row| row.base.fetch(component, 0) }) }, money(quote.base_cents), money(quote.discount_cents), money(quote.value_cents) ] } ])
  end
  valores = [ [ "Valor do acordo", money(quote.value_cents) ] ]
  valores << [ "Crédito do contrato usado como abatimento", money(quote.credit.total) ] if quote.credit.rebate?
  valores << [ "Valor líquido do acordo", money(quote.net_cents) ]
  valores << [ "Crédito do contrato usado na entrada", "#{money(quote.credit.total)}, faltam #{money(quote.down_payment_cents - quote.credit.total)} da entrada" ] if quote.credit.down_payment?
  valores << [ "Entrada", "#{money(quote.down_payment_cents)} em #{date_br(quote.down_payment_on)}" ]
  if quote.installments.any?
    valores << [ "Método", "#{t("agreements.methods.#{quote.method}")}#{" a #{percent_decimal(quote.rate_pct)} ao mês" unless quote.method == "none"}" ]
    valores << [ "Taxa efetiva anual", percent_decimal(quote.effective_annual_pct) ]
    valores << [ "Juros do parcelamento", money(quote.interest_cents) ]
  end
  valores << [ "Soma total a pagar", money(quote.total_cents) ]
  json.valores(valores.map { |rotulo, valor| { rotulo: rotulo, valor: valor } })
  json.parcelas(quote.schedule.map { |row| { titulo: row.number.zero? ? "Entrada" : "Parcela #{row.number}", vencimento: date_br(row.due), valor: money(row.amount_cents), juros: money(row.interest_cents), amortizacao: money(row.amortization_cents), falta: money(row.balance_cents) } })
end
