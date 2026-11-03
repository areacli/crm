# Página do título na SPA (R100, 09 R174; decisão 0025): situação, valores, a cobrança que o prende, a memória de cálculo, as versões e a linha do tempo.
bill = @bill
json.id bill.id
json.numero bill.number
json.credor bill.tenant.name
json.cliente bill.customer.name
json.cliente_id bill.customer_id
situacao = if bill.withdrawn? then selo("Retirado", :neutral)
elsif bill.paid? then selo("Pago", :success)
elsif bill.due_date < Date.current then selo("Vencido", :danger)
else selo("A vencer", :info)
end
json.selo situacao
indicadores = [ { rotulo: "Valor vigente", valor: money(bill.amount_cents) }, { rotulo: "Pago", valor: money(bill.paid_cents) }, { rotulo: "Saldo", valor: money(bill.balance_cents) } ]
indicadores << { rotulo: "Excedente", valor: money(bill.excess_cents), definicao: "Crédito do contrato: o que foi pago além do valor do título." } if bill.excess_cents.positive?
indicadores << { rotulo: "Vencimento", valor: date_br(bill.due_date), detalhe: "Contrato #{bill.contract.label}#{" · #{bill.product}" if bill.product.present?}" }
json.indicadores indicadores

# Cada nota é um texto e, quando cita um acordo, o número e o id para o link.
notas = []
notas << { texto: bill.kind_break? ? "Título da quebra do acordo" : "Título de acordo", acordo: bill.agreement.number, acordo_id: bill.agreement_id } if bill.agreement_id
notas << { texto: "Título de estorno, fora do acordo", acordo: bill.origin_agreement.number, acordo_id: bill.origin_agreement.id } if bill.kind_reversal?
notas << { texto: "Renegociado no acordo", acordo: @renegotiated_by.number, acordo_id: @renegotiated_by.id } if @renegotiated_by
notas << { texto: "Em promessa #{@held_promise.label}" } if @held_promise
notas << { texto: @held_agreement.proposal? ? "Em proposta" : "Em acordo", acordo: @held_agreement.number, acordo_id: @held_agreement.id } if @held_agreement
json.notas notas

composicao = if @valuation && (bill.agreement_id || bill.kind_reversal?)
  [ [ "Multa", @valuation.fine_cents ], [ "Juros", @valuation.interest_cents ], [ "Honorários e correção", @valuation.fees_cents ], [ "Saldo devedor", @valuation.total_cents ] ]
elsif @valuation
  [ [ "Principal", @valuation.principal_cents ], [ "Principal corrigido", @valuation.corrected_principal_cents ], [ "Multa", @valuation.fine_cents ], [ "Juros", @valuation.interest_cents ],
    [ "Honorários", @valuation.fees_cents ], [ "Atualizado", @valuation.total_cents ] ]
else
  []
end
json.composicao(composicao.map { |rotulo, centavos| { rotulo: rotulo, valor: money(centavos) } })
congelado = @valuation && (bill.agreement_id || bill.kind_reversal?)
json.nota_da_composicao(congelado ? "Saldo devedor pelos parâmetros congelados no acordo#{" (só principal e correção têm encargos, sem multa nova)" if bill.kind_reversal?}." : nil)

if @memory
  decimal = ->(value, digits) { format("%.#{digits}f", value).tr(".", ",") }
  json.memoria do
    json.legenda "Pelos parâmetros de #{bill.tenant.name}, em #{date_br(@today)}"
    json.pode_ver_indices @can_see_indexes
    json.periodos(@memory.stretches.map do |stretch|
      { periodo: "#{date_br(stretch[:from])} a #{date_br(stretch[:to])}", dias: number_br(stretch[:days]), enquadramento: stretch[:tier], correcao: stretch[:correction],
        fator: decimal.call(stretch[:factor], 6), juros: stretch[:interest_origin], taxa: "#{decimal.call(stretch[:rate], 6)}%", meses: decimal.call(stretch[:months], 4),
        base: money(stretch[:base]), juros_do_periodo: money(stretch[:interest]) }
    end)
    json.observacoes(@memory.stretches.flat_map { |stretch| stretch[:notes].map { |note| "#{date_br(stretch[:from])} a #{date_br(stretch[:to])}: #{note}" } } + @memory.notes)
  end
else
  json.memoria nil
end

total = @history.versions.size
json.versoes(@history.versions.each_with_index.map do |version, index|
  { versao: "#{index + 1}#{" (vigente)" if index == total - 1}", valor: money(version.amount_cents), data: datetime_br(version.created_at),
    importacao: version.import ? "de #{date_br(version.import.created_at.in_time_zone.to_date)}" : "—", confirmada_por: version.user&.name || "—" }
end)
json.eventos(@history.events.map { |event| { data: date_br(event.date), texto: event.text, valor: event.cents ? money(event.cents) : "—" } })
