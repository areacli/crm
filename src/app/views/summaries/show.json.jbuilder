# Resumo da carteira na SPA (R23; decisão 0025): os indicadores com a definição de cada um e os cartões como tabelas genéricas (colunas e
# linhas já formatadas), para a tela desenhar todos do mesmo jeito. Os mesmos números e textos da página do servidor.
summary = @summary
json.vazio summary.nil?
json.referencia "Referência #{date_br(Date.current)}"
if summary
  hide_upcoming = summary[:upcoming_display] != "separate" && summary[:upcoming_display] != "summed"
  agr = summary[:agreements]
  kpi = ->(rotulo, valor, definicao, detalhe = nil) { { rotulo: rotulo, valor: valor, detalhe: detalhe, definicao: definicao } }
  json.indicadores [
    kpi.("Clientes em cobrança", number_br(summary[:customers]), "Clientes com ao menos um título em cobrança nos credores que você consulta."),
    kpi.("Títulos", number_br(summary[:bills]), "Títulos em cobrança, vencidos e a vencer."),
    kpi.("Vencido", money(summary[:overdue_cents]), "Saldo dos títulos vencidos, pelo valor original menos o pago.", (summary[:upcoming_display] == "summed" ? "Com a vencer: #{money(summary[:overdue_cents] + summary[:upcoming_cents])}" : nil)),
    kpi.("A vencer", (hide_upcoming ? "—" : money(summary[:upcoming_cents])), "Saldo dos títulos ainda no prazo. Cada credor escolhe se o mostra à parte, somado ao vencido ou só na ficha."),
    kpi.("Atualizado", money(summary[:updated][:total_cents]), "Principal corrigido, multa, juros e honorários dos títulos vencidos, pelas regras de cada credor, até a data do último cálculo.",
         (summary[:updated][:calculated_on] ? "até #{date_br(summary[:updated][:calculated_on])}" : nil)),
    kpi.("Créditos dos contratos", money(summary[:credit_cents]), "Crédito disponível nos contratos. Inclui o excedente de título com valor reduzido; não entra no recuperado.")
  ]
  json.recuperacao [
    *summary[:recovered].map { |month| kpi.("Recuperado em #{month[:label]}", money(month[:total_cents]), "O que foi aplicado a títulos pela data do pagamento, menos os estornos conforme a política de cada credor. Crédito e pagamento pendente não entram.") },
    kpi.("Pagamentos pendentes", number_br(summary[:pending_count]), "Pagamentos recebidos que ainda não se ligaram a um título.", money(summary[:pending_cents])),
    kpi.("Dos quais em acordo", money(agr[:in_agreement_cents]), "Valor dos títulos em acordo em #{agr[:label]}. Já está no total em cobrança; não se soma duas vezes.", "#{number_br(agr[:in_agreement_count])} acordos"),
    kpi.("Acordos aceitos no mês", number_br(agr[:accepted]), "Acordos aceitos em #{agr[:label]}.", money(agr[:accepted_cents])),
    kpi.("Desconto concedido no mês", money(agr[:discount_total]), "Contado na efetivação do acordo; o acordo cancelado depois dela o tira no mês do cancelamento.")
  ]

  methods = summary[:recovered].flat_map { |month| month[:methods].keys }.uniq.sort_by { |method| -summary[:recovered].sum { |month| month[:methods][method].to_i } }
  # Os cartões com colunas por período (meses, janelas de 7 e 30 dias) trazem as colunas e as células de cada linha.
  json.recuperado_por_meio do
    json.colunas([ { texto: "Meio", numero: false }, *summary[:recovered].map { |month| { texto: month[:label], numero: true } } ])
    json.linhas(methods.map { |method| { celulas: [ t("payments.methods.#{method}"), *summary[:recovered].map { |month| month[:methods][method] ? money(month[:methods][method]) : "—" } ] } })
  end
  json.acordos_por_mes do
    json.mes agr[:label]
    json.anterior agr[:previous_label]
    linhas = [ [ "Aceitos", number_br(agr[:accepted]), number_br(agr[:previous][:accepted]) ], [ "Quebrados", number_br(agr[:broken]), number_br(agr[:previous][:broken]) ],
               [ "Quitados", number_br(agr[:settled]), number_br(agr[:previous][:settled]) ], [ "Ativos em dia", number_br(agr[:on_time]), "—" ], [ "Ativos em atraso", number_br(agr[:late]), "—" ] ]
    linhas << [ "Estornos à espera do gestor", number_br(agr[:waiting]), "—" ] if agr[:waiting].positive?
    json.linhas(linhas.map { |situacao, mes, anterior| { situacao: situacao, mes: mes, anterior: anterior } })
  end
  json.descontos([ [ "Desconto concedido", money(agr[:discount_total]) ], *agr[:discounts].map { |component, cents| [ "Desconto: #{t("agreements.components.#{component}").downcase}", money(cents) ] },
                   *agr[:abatements].map { |kind, cents| [ "Abatimento: #{t("agreements.abatement_kinds.#{kind}").downcase}", money(cents) ] } ].map { |rotulo, valor| { rotulo: rotulo, valor: valor } })
  json.acionamentos do
    json.colunas([ { texto: "Tipo do resultado", numero: false }, *summary[:contacts].flat_map { |window| [ { texto: "#{window[:days]} dias: acionamentos", numero: true }, { texto: "#{window[:days]} dias: clientes", numero: true } ] } ])
    json.linhas([ [ "Total", summary[:contacts].map { |window| window[:total] } ], *ContactResult::KINDS.keys.map { |kind| [ t("contacts.kinds.#{kind}"), summary[:contacts].map { |window| window[:kinds][kind] } ] } ].map do |tipo, contas|
      { celulas: [ tipo, *contas.flat_map { |conta| [ number_br(conta[:attempts]), number_br(conta[:customers]) ] } ] }
    end)
  end
  json.promessas do
    json.colunas([ { texto: "Indicador", numero: false }, *summary[:promises].map { |window| { texto: "Últimos #{window[:days]} dias", numero: true } } ])
    json.linhas([ [ "Promessas registradas", :promises ], [ "Promessas cumpridas", :fulfilled ], [ "Cumpridas com atraso", :late ], [ "Quebradas", :broken ] ].map { |label, key| { celulas: [ label, *summary[:promises].map { |window| number_br(window[key]) } ] } })
  end
  if summary[:labels].nil?
    json.aviso_das_faixas "As faixas são configuradas por credor e diferem entre os credores que você consulta; por isso as tabelas por faixa não aparecem. Os totais acima valem para todos."
  else
    faixas = ->(rows) do
      maximum = [ rows.sum { |row| row[:cents] }, 1 ].max
      rows.map { |row| { faixa: row[:label], quantidade: number_br(row[:count]), vencido: money(row[:cents]), atualizado: money(row[:updated_cents]), proporcao: (row[:cents] * 100.0 / maximum).round(1) } }
    end
    json.faixas_por_cliente faixas.(summary[:by_customer])
    json.faixas_por_titulo faixas.(summary[:by_bill])
  end
end
