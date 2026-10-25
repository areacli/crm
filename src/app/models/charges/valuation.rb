module Charges
  # Valor atualizado de um título (R164 a R172) a partir do que o `Reader` leu: vencimento prorrogado para o dia útil nacional (M7), histórico
  # do contrato, regras com as versões (AN1) e os encargos já alocados descontados (R226).
  class Valuation
    def initialize(tables:, rules:, demais_id:, versions: nil)
      @tables = tables
      @rules = rules
      @demais_id = demais_id
      @versions = versions
    end

    def call(input, as_of: nil, memory: false)
      segment = input.segment_id || @demais_id
      periods = input.periods.empty? ? input.periods : input.periods.map { |since, id| [ since, id || @demais_id ] }
      Calculator.call(@tables, @rules, input.amount, BusinessDays.next_business(input.due), payments: input.payments, periods: periods, segment_today: segment,
                                                                                               memory: memory, as_of: as_of, versions: @versions, consolidated: input.dates.to_a)
                .minus_paid(input.paid)
    end
  end
end
