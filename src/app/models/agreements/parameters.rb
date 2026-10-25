module Agreements
  # Parâmetros de encargos do acordo, com override no segmento (11, R207a): cada campo do segmento vazio herda o do credor. Servem à simulação (taxa e método
  # do parcelamento) e ao motor do título de acordo (mora). Os acordos congelam o que valia no dia da proposta (R210), então mudar estes campos não muda título nenhum.
  module Parameters
    Installment = Data.define(:rate_pct, :method)

    module_function

    def installment(setting, segment)
      Installment.new((segment&.installment_rate_pct || setting.installment_rate_pct).to_d, segment&.installment_method || setting.installment_method)
    end

    # Encargos de atraso do título de acordo (R228), pelos parâmetros do credor e do segmento: multa, juros de mora e índice são os da regra de encargos
    # do segmento (09, R160); a convenção de dias e a base da multa são os próprios do acordo (R207a, DA22); honorários só com a marca do contrato (R160).
    # Segmento com taxa legal: o acordo usa a taxa de juros de mora do credor, que é o parâmetro (a taxa legal varia por mês e o acordo congela taxas).
    def late_rule(setting, segment)
      rule = Charges::Rule.build(Charges::RuleSet.segment_values(segment || Segment.new), Charges::RuleSet.params_of(setting))
      rate = rule.interest == "" ? 0.0 : (segment&.interest_pct || setting.charge_interest_pct).to_f / 100
      Charges::AgreementRule.new(rule.fine, rate, rule.form, segment&.agreement_days_convention || setting.agreement_days_convention,
                                 segment&.agreement_fine_base || setting.agreement_fine_base, rule.index, rule.fees)
    end

    # Tudo o que a proposta congela dos parâmetros (R210).
    def frozen(setting, segment)
      installment = self.installment(setting, segment)
      { "installment_rate_pct" => installment.rate_pct.to_s("F"), "installment_method" => installment.method, "late_rule" => late_rule(setting, segment).to_storage }
    end
  end
end
