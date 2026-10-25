module Charges
  # Valor atualizado de um título (R164 a R172), em Ruby puro. Porta do motor medido no plano da 09 (dias como inteiros, fatores por dia numa
  # tabela, arredondamento em inteiros): componentes em ponto flutuante de dupla precisão (em R$ 1 milhão o erro fica milhões de vezes abaixo de
  # um centavo) e cada componente arredondado ao centavo pela regra da NBR 5891 (metade para o par), uma vez só (R169).
  module Calculator
    LAW_CUT = Date.new(2024, 8, 30) # Lei 14.905/2024; Resolução CMN 5.171, art. 8º, parágrafo único (R181)
    LAW_K = Tables.k(LAW_CUT) - 1 # fim de 29/08/2024
    BLANK = Rule.blank

    module_function

    # Metade para o par (NBR 5891). O valor é limpo da sujeira binária antes, para que 20,125 não caia do lado errado.
    def round_cents(value)
      floor = value.floor
      diff = value - floor
      return floor + 1 if diff > 0.500000001
      return floor if diff < 0.499999999

      floor + (floor.odd? ? 1 : 0)
    end

    # tab: Charges::Tables; rules: { segmento => Rule }; amount: valor vigente em centavos; due: vencimento (já com a prorrogação do dia não útil);
    # payments: [[data, centavos de principal]] líquidos de estorno; periods: [[desde, segmento]] do histórico do contrato, em ordem;
    # segment_today: o segmento vigente. `as_of`: data do cálculo (R226, o valor na data do pagamento), nunca depois de tab.today.
    # AN1: `consolidated` são as datas dos pagamentos do título e `versions.call(segmento, data)` dá a regra vigente numa data; o encargo até cada
    # pagamento fica pela regra vigente nele, e só o trecho depois do último pagamento usa a regra atual. Sem pagamento, a regra atual desde o vencimento.
    def call(tab, rules, amount, due, payments: [], periods: [], segment_today: nil, memory: false, as_of: nil, versions: nil, consolidated: [])
      policies = tab.policies
      kv = Tables.k(due)
      kh = Tables.k([ as_of || tab.today, tab.today ].min)
      # Caminho mais comum, sem alocar nada além do resultado: sem pagamento, sem histórico de segmento e sem pagamento consolidado.
      if !memory && payments.empty? && periods.empty? && consolidated.empty? && kv < kh && amount.positive?
        quick = quick_path(tab, rules, amount, kv, kh, segment_today, policies)
        return quick if quick
      end
      paid_before = payments.sum { |date, value| Tables.k(date) <= kv ? value : 0 }
      balance = [ amount - paid_before, 0 ].max
      return Result.new(principal: [ amount - payments.sum { |_, value| value }, 0 ].max) if kv >= kh || balance <= 0

      # Pagamento com a data do próprio cálculo (ou depois, M5) abate o principal no fim, sem mudar os encargos até essa data.
      paid_at_end = payments.sum { |date, value| Tables.k(date) >= kh ? value : 0 }
      blank = Rule.blank
      periods = periods.presence || [ [ due, segment_today ] ]
      first = periods.first[1]
      law_k = Tables.k(LAW_CUT) - 1 # fim de 29/08/2024
      closings = versions ? consolidated.map { |date| Tables.k(date) }.select { |k| k > kv && k <= kh }.uniq.sort : []
      today_rule = nil

      finish = lambda do |r|
        if paid_at_end.positive?
          r.principal = [ r.principal - paid_at_end, 0 ].max
          r.corrected_principal = [ r.corrected_principal - paid_at_end, r.principal ].max
          r.fees = round_cents((r.corrected_principal + r.fine + r.interest) * today_rule.fees)
          r.recompute_total!
        end
        r
      end

      segment_at = lambda do |k| # o dia cujo fim é k+1 começa no fim de k; DE4: antes do histórico vale o primeiro registrado
        day = Tables.day(k + 1)
        current = first
        periods.each { |since, segment| since <= day ? current = segment : break }
        current
      end

      rule_for = lambda do |segment, b| # regra do trecho que termina em b: a vigente no pagamento que o fecha (AN1), ou a atual
        closing = closings.find { |k| k >= b }
        next rules.fetch(segment, blank) if closing.nil?

        versions.call(segment, Tables.day(closing)) || rules.fetch(segment, blank)
      end

      single = !memory && periods.all? { |_, segment| segment == first } && payments.none? { |date, _| kv < Tables.k(date) && Tables.k(date) < kh } && closings.empty?
      if single
        # Caminho rápido: um trecho só, sem pagamento depois do vencimento nem troca de segmento (a maior parte da carteira). Mesmo resultado do
        # caminho geral (teste "caminho rápido igual ao geral").
        rule = rules.fetch(first, blank)
        unless rule.interest == "legal" && kv < law_k && law_k < kh
          factor, rate, = stretch_rate(rule, tab, kv, kh, kh <= law_k, policies, kv)
          corrected = balance * factor
          base = policies.negative_index == "floor" ? [ corrected, balance ].max : corrected
          fine_base = rule.fine_base == "face" ? balance : base
          pc = round_cents(base)
          fine = round_cents(fine_base * rule.fine)
          interest = round_cents(base * rate)
          today_rule = rules.fetch(segment_today.nil? ? first : segment_today, blank)
          fees = round_cents((pc + fine + interest) * today_rule.fees)
          return finish.call(Result.new(principal: balance, corrected_principal: pc, fine: fine, interest: interest, fees: fees, total: pc + fine + interest + fees))
        end
      end

      payment_at = Hash.new(0)
      payments.each { |date, value| k = Tables.k(date); payment_at[k] += value if kv < k && k < kh }
      cuts = [ kv, kh, *payment_at.keys, *closings.select { |k| k < kh } ].to_set
      previous = first
      periods.drop(1).each do |since, segment|
        cuts << (Tables.k(since) - 1) if segment != previous && kv < Tables.k(since) - 1 && Tables.k(since) - 1 < kh
        previous = segment
      end
      cuts << law_k if kv < law_k && law_k < kh
      cuts = cuts.to_a.sort

      stretches = []
      nominal = balance
      corrected = balance.to_f
      cuts.each_cons(2) do |a, b|
        segment = segment_at.call(a)
        rule = rule_for.call(segment, b)
        factor, rate, origin, months = stretch_rate(rule, tab, a, b, b <= law_k, policies, kv, memory)
        stretches << { a: a, b: b, segment: segment, rule: rule, nominal: nominal, corrected: corrected, factor: factor, rate: rate, origin: origin, months: months }
        corrected *= factor
        if payment_at.key?(b)
          nominal = [ nominal - payment_at[b], 0 ].max
          corrected = [ corrected - payment_at[b], 0.0 ].max
        end
      end
      until_today = 1.0
      stretches.reverse_each { |s| until_today *= s[:factor]; s[:until_today] = until_today }
      floor = policies.negative_index == "floor"
      principal_corrected = floor ? [ corrected, nominal ].max : corrected
      interest = 0.0
      stretches.each do |s|
        base = s[:corrected] * s[:until_today]
        base = [ base, s[:nominal] ].max if floor
        s[:base] = base
        interest += base * s[:rate]
      end
      fine_rule = rule_for.call(segment_at.call(kv), kv + 1) # AN1: a multa fica pela regra vigente no primeiro pagamento
      fine_base = balance * stretches.first[:until_today]
      fine_base = [ fine_base, balance ].max if floor
      fine_base = balance if fine_rule.fine_base == "face"
      pc = round_cents(principal_corrected)
      fine = round_cents(fine_base * fine_rule.fine)
      interest = round_cents(interest)
      today_rule = rules.fetch(segment_today.nil? ? segment_at.call(kh - 1) : segment_today, blank)
      fees = round_cents((pc + fine + interest) * today_rule.fees)
      result = Result.new(principal: nominal, corrected_principal: pc, fine: fine, interest: interest, fees: fees, total: pc + fine + interest + fees)
      add_memory(result, tab, stretches, due, periods, rules, first, fine_rule, today_rule, floor, corrected, nominal) if memory
      finish.call(result)
    end

    # Um trecho só, desde o vencimento até a data do cálculo: o caso da maior parte da carteira. Devolve nil quando os juros legais atravessam o corte
    # de 30/08/2024 (precisa de dois trechos) e o caminho geral calcula. O mesmo resultado do caminho geral (teste "caminho rápido igual ao geral").
    def quick_path(tab, rules, amount, kv, kh, segment_id, policies)
      rule = rules.fetch(segment_id, BLANK)
      law_k = LAW_K
      return nil if rule.interest == "legal" && kv < law_k && law_k < kh

      factor, rate, = stretch_rate(rule, tab, kv, kh, kh <= law_k, policies, kv)
      corrected = amount * factor
      base = policies.negative_index == "floor" && amount > corrected ? amount : corrected
      fine_base = rule.fine_base == "face" ? amount : base
      pc = round_cents(base)
      fine = round_cents(fine_base * rule.fine)
      interest = round_cents(base * rate)
      fees = round_cents((pc + fine + interest) * rule.fees)
      Result.new(principal: amount, corrected_principal: pc, fine: fine, interest: interest, fees: fees, total: pc + fine + interest + fees)
    end

    # Fator de correção e taxa de juros do trecho (a, b] e o que a memória mostra. Juros compostos contam desde o vencimento (kv) em cada trecho,
    # para a soma dos trechos dar a capitalização do período inteiro.
    def stretch_rate(rule, tab, a, b, old, policies, kv, describe = false)
      no_correction = old && rule.interest == "legal" && policies.old_legal == "selic"
      factor = 1.0
      if rule.index != "" && !no_correction
        table = tab.corr.fetch(rule.index)
        factor = table[b] / table[a]
      end
      months = tab.pos[b] - tab.pos[a]
      simple = rule.form == "simple"
      form = simple ? "simples" : "compostos" if describe
      if rule.interest == "fixed" && rule.convention == "thirty"
        rate = simple ? rule.rate / 30 * (b - a) : (1 + rule.rate / 30)**(b - kv) - (1 + rule.rate / 30)**(a - kv)
        origin = ("#{pct(rule.rate)}% ao mês ÷ 30 por dia, #{form}" if describe)
      elsif rule.interest == "fixed"
        rate = simple ? rule.rate * months : (1 + rule.rate)**(tab.pos[b] - tab.pos[kv]) - (1 + rule.rate)**(tab.pos[a] - tab.pos[kv])
        origin = ("#{pct(rule.rate)}% ao mês, #{form}" if describe)
      elsif rule.interest == "legal" && old
        case policies.old_legal
        when "selic" then rate, origin = tab.interest["selic"][b] - tab.interest["selic"][a], "Selic do mês (antes de 30/08/2024), sem correção"
        when "one_percent" then rate, origin = 0.01 * months, "1% ao mês (antes de 30/08/2024)"
        else rate, origin = 0.0, "sem juros antes de 30/08/2024"
        end
      elsif rule.interest == "legal"
        rate, origin = tab.interest["legal"][b] - tab.interest["legal"][a], "taxa legal (série 29543)"
      else
        rate, origin = 0.0, "sem juros"
      end
      [ factor, rate, origin, months ]
    end

    def pct(fraction) = format("%.4g", fraction * 100).sub(".", ",")

    def add_memory(result, tab, stretches, due, periods, rules, first, fine_rule, today_rule, floor, corrected, nominal)
      result.stretches = stretches.map { |s| stretch_memory(tab, s) }
      result.notes << "Vencimento em #{due.strftime('%d/%m/%Y')}, antes de janeiro de 2000: a correção e os juros contam desde 01/01/2000, primeiro mês dos índices." if due < Tables::START
      if periods.first[0] > due
        result.notes << "O histórico de segmento começa em #{periods.first[0].strftime('%d/%m/%Y')}; antes disso vale o primeiro segmento registrado, #{rules.fetch(first, Rule.blank).name}."
      end
      result.notes << "Multa de #{pct(fine_rule.fine)}% (#{fine_rule.name}) sobre o principal em aberto no dia seguinte ao vencimento, #{fine_rule.fine_base == 'face' ? 'sobre o valor de face' : 'corrigido até hoje'}."
      result.notes << "Honorários de #{pct(today_rule.fees)}% (#{today_rule.name}) sobre principal corrigido, multa e juros." if today_rule.fees.positive?
      result.notes << "A deflação deixaria o principal corrigido abaixo do principal: vale o principal (política Índice negativo)." if floor && corrected < nominal
    end

    NAMES = { "" => "sem correção", "ipca" => "IPCA", "inpc" => "INPC", "igpm" => "IGP-M" }.freeze

    def stretch_memory(tab, s)
      from = Tables.day(s[:a] + 1)
      to = Tables.day(s[:b])
      notes = []
      if s[:rule].index != ""
        month = from.beginning_of_month
        while month <= to
          note = tab.notes[s[:rule].index][month]
          notes << "#{NAMES[s[:rule].index]} de #{month.strftime('%m/%Y')}: #{note}" if note
          month = month.next_month
        end
      end
      { from: from, to: to, days: s[:b] - s[:a], segment: s[:rule].name, correction: NAMES[s[:rule].index], factor: s[:factor], interest_origin: s[:origin],
        rate: s[:rate] * 100, months: s[:months], base: round_cents(s[:base]), interest: round_cents(s[:base] * s[:rate]), notes: notes }
    end
  end
end
