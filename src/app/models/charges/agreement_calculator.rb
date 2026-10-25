module Charges
  # Encargos do título de acordo atrasado (11, R228): multa, juros de mora, correção e honorários, só sobre o principal e a correção herdados (nunca
  # sobre juros do parcelamento, multa, juros ou mora), até a data do pagamento, como o boleto. Ruby puro e centavos inteiros, cada componente arredondado
  # uma vez pela NBR 5891 (metade para o par), como o motor da 09. O título da quebra e o título de estorno não têm multa nova (`fine: false`).
  module AgreementCalculator
    Result = Data.define(:fine, :interest, :correction, :fees) do
      def total = fine + interest + correction + fees

      # Na ordem em que um pagamento os cobre (10, R195): juros, multa, honorários, correção.
      def components = { "interest" => interest, "fine" => fine, "fees" => fees, "correction" => correction }.select { |_, cents| cents.positive? }
    end

    NONE = Result.new(0, 0, 0, 0)

    module_function

    # `principal` e `correction`: o que o título carrega herdado dos originais, em centavos; `due`: vencimento (já em dia útil); `paid_on`: a data do
    # pagamento ou do cálculo. `tables`: `Charges::Tables` até `paid_on`, para o índice de correção e a convenção por mês do calendário.
    def call(rule, principal:, correction:, due:, paid_on:, tables: nil, fine: true)
      base = principal + correction
      return NONE if base <= 0 || paid_on <= due || !rule.charges?

      days = (paid_on - due).to_i
      factor = correction_factor(rule, tables, due, paid_on)
      corrected = Calculator.round_cents(base * factor)
      correction_late = corrected - base
      interest_base = base * factor
      fine_base = rule.fine_base == "face" ? principal : interest_base
      fine_cents = fine ? Calculator.round_cents(fine_base * rule.fine) : 0
      interest_cents = Calculator.round_cents(interest_base * interest_rate(rule, tables, due, paid_on, days))
      fees_cents = Calculator.round_cents((corrected + fine_cents + interest_cents) * rule.fees)
      Result.new(fine_cents, interest_cents, correction_late, fees_cents)
    end

    # Fator do índice entre o vencimento e a data (nunca abaixo de 1 com a política "Índice negativo: o principal não cai", a mesma da 09, R165).
    def correction_factor(rule, tables, due, paid_on)
      return 1.0 if rule.index == "" || tables.nil?

      table = tables.corr.fetch(rule.index)
      factor = table[Tables.k([ paid_on, tables.today ].min)] / table[Tables.k(due)]
      tables.policies.negative_index == "floor" ? [ factor, 1.0 ].max : factor
    end

    # Taxa de juros do período em fração. `thirty`: taxa ÷ 30 por dia corrido (simples ou composta); `calendar`: pela fração do mês do calendário.
    def interest_rate(rule, tables, due, paid_on, days)
      simple = rule.form == "simple"
      if rule.convention == "calendar" && tables
        months = tables.pos[Tables.k([ paid_on, tables.today ].min)] - tables.pos[Tables.k(due)]
        simple ? rule.rate * months : (1 + rule.rate)**months - 1
      else
        simple ? rule.rate / 30 * days : (1 + rule.rate / 30)**days - 1
      end
    end
  end
end
