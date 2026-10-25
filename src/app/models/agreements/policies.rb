module Agreements
  # Políticas do credor para os acordos (11, tabela "Políticas do credor e do segmento"): o esquema de cada uma (opções, padrão, se congela no acordo, em
  # que aba aparece) fica aqui, e o credor guarda em `tenant_settings.agreement_policies` só o que escolheu; o que falta vale o padrão. A mesma decisão
  # da promessa: política por coluna dá uma migração a cada uma, e estas são 33. As políticas de uma só opção da tabela ("Forma: novação" e "Cobrança das
  # parcelas: o credor emite") não têm escolha e ficam fora. A política do crédito "Prazo para crédito sem uso ir à devolução" (N17) está adiada com a
  # devolução (MT-25, R232c). Cada política tem rótulo, ajuda e opções em `config/locales/agreements.pt-BR.yml`.
  module Policies
    # `options`: as escolhas, a primeira é o padrão (`default`); `freezes`: se o acordo congela o valor do dia da proposta (R210); `tab`: `:agreements`
    # ("Promessas e acordos") ou `:payments` ("Pagamentos"). `kind`: `:choice` ou `:amount` (percentual ou reais).
    Entry = Data.define(:key, :kind, :options, :default, :freezes, :tab, :spec)

    def self.choice(key, options, freezes:, tab: :agreements, spec: nil) = Entry.new(key, :choice, options, options.first, freezes, tab, spec)

    # Valor em reais ou em percentual (R228a, R229): { "kind" => "cents" | "percent", "value" => centavos ou percentual }.
    def self.amount(key, default, freezes:, tab: :agreements, spec: nil, kinds: %w[cents percent]) =
      Entry.new(key, :amount, kinds, { "kind" => kinds.first, "value" => default }, freezes, tab, spec)

    SCHEMA = [
      choice("effectuation", %w[payment acceptance], freezes: true, spec: "N5"),
      choice("cash_effectuation", %w[follows payment_only], freezes: true, spec: "P4"),
      choice("late_down_payment", %w[with_late_charges credit_only], freezes: true, spec: "N6"),
      choice("partial_down_payment", %w[by_composition oldest_first], freezes: true, spec: "AC10"),
      choice("installment_number_before_effectuation", %w[as_down_payment allocated_only], freezes: true, spec: "AC11"),
      choice("bank_reversal", %w[new_term since_due], freezes: true, spec: "N10, Q5"),
      choice("first_period", %w[table_plus_days recalculated], freezes: true, spec: "N15"),
      choice("break_form", %w[installments_follow single_title], freezes: true, spec: "DA6"),
      choice("reactivation", %w[reactivates common_payment], freezes: true, spec: "DA16"),
      choice("original_paid_before", %w[cancels counts_as_agreement], freezes: true, spec: "DA7"),
      choice("late_charges", %w[by_parameters none], freezes: true, spec: "DA10, N18"),
      choice("fees", %w[on_negotiated on_base], freezes: true, spec: "DA30"),
      choice("credit_reversal_origin", %w[new_title reopen_down_payment], freezes: true, spec: "U1"),
      choice("early_settlement", %w[calculated_value payment_date_value], freezes: true, spec: "S5"),
      choice("early_payment", %w[discounts full_value], freezes: true, spec: "DA35, N16"),
      choice("who_accepts", %w[financial_or_holder financial_only], freezes: true, spec: "MTD4"),
      choice("credit_across_contracts", %w[same_contract sum], freezes: true, spec: "A6"),
      choice("credit_order", %w[oldest_first contract_first], freezes: true, spec: "A6"),
      choice("renegotiate_active", %w[no yes], freezes: false, spec: "DA29"),
      choice("renegotiate_partial", %w[all partial], freezes: false, spec: "M14"),
      choice("promise_after_acceptance", %w[promise down_payment], freezes: false, spec: "DA27"),
      choice("credit_use", %w[in_agreement record_only], freezes: false, tab: :payments, spec: "DA23"),
      choice("credit_entry", %w[down_payment rebate], freezes: false, tab: :payments, spec: "DA15"),
      choice("credit_and_break", %w[suspends before_break after_break], freezes: false, tab: :payments, spec: "DA23"),
      choice("credit_and_late_down_payment", %w[credit_pays notice], freezes: false, tab: :payments, spec: "U2, V2"),
      choice("renegotiated_payment", %w[credit rebate_oldest], freezes: false, tab: :payments, spec: "DA8"),
      choice("overpayment", %w[credit rebate_next], freezes: false, tab: :payments, spec: "DA9"),
      choice("reversal_withdrawal", %w[reapply_all reapply_settlements], freezes: false, tab: :payments, spec: "V4"),
      # Tolerâncias de valor (R228a, N3): três, cada uma em reais ou em percentual. Só a dos títulos de acordo congela.
      amount("tolerance_agreement", 100, freezes: true, spec: "N3"),
      amount("tolerance_promise", 0, freezes: false, spec: "N3"),
      amount("tolerance_direct", 0, freezes: false, tab: :payments, spec: "N3"),
      # Mínimo para quebrar e efetivar (M1, R229): em reais, em percentual do valor líquido do acordo ou igual à tolerância dos títulos de acordo.
      amount("minimum_to_break", 0, freezes: true, spec: "M1", kinds: %w[cents percent tolerance]),
      choice("minimum_sum", %w[all_overdue beyond_break_days], freezes: true, spec: "Q2")
    ].freeze

    BY_KEY = SCHEMA.index_by(&:key).freeze

    module_function

    def entry(key) = BY_KEY.fetch(key.to_s)

    def keys(tab = nil) = SCHEMA.select { |entry| tab.nil? || entry.tab == tab }.map(&:key)

    # Os valores efetivos do credor: o que ele escolheu e, no resto, o padrão.
    def for(setting)
      stored = setting.agreement_policies || {}
      SCHEMA.to_h { |entry| [ entry.key, valid?(entry, stored[entry.key]) ? stored[entry.key] : entry.default ] }
    end

    def value(setting, key) = self.for(setting).fetch(key.to_s)

    # As políticas que o acordo congela na proposta (R210), com o valor do dia.
    def frozen_for(setting) = self.for(setting).slice(*SCHEMA.select(&:freezes).map(&:key))

    def valid?(entry, value)
      case entry.kind
      when :choice then entry.options.include?(value)
      else value.is_a?(Hash) && entry.options.include?(value["kind"]) && value["value"].is_a?(Integer) && value["value"] >= 0 &&
                              (value["kind"] != "percent" || value["value"] <= 10_000)
      end
    end

    # Tolerância de valor em centavos sobre `total` (o devido do título): em reais, o valor; em percentual (guardado em centésimos de ponto: 150 = 1,5%),
    # a fração do devido arredondada para baixo (R228a).
    def tolerance_cents(setting, key, total)
      entry = BY_KEY.fetch("tolerance_#{key}")
      stored = (setting.agreement_policies || {})[entry.key]
      tolerance_of(valid?(entry, stored) ? stored : entry.default, total)
    end

    # A tolerância guardada ({kind, value}) em centavos sobre `total`; o acordo usa a que congelou na proposta (R210).
    def tolerance_of(spec, total)
      return 0 unless spec && spec["value"].to_i.positive?

      spec["kind"] == "percent" ? (total * spec["value"] / 10_000) : spec["value"]
    end
  end
end
