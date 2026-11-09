module Agreements
  # Lê o formulário da simulação (11, R211 a R213): títulos, à vista ou parcelado, o desconto por componente em percentual (vírgula ou ponto, até duas casas),
  # a entrada (valor e vencimento), as parcelas e o dia de vencimento. Valor ilegível levanta Refused com o campo, e o formulário volta com a mensagem.
  module FormParams
    PERCENT = /\A\d{1,3}(?:[.,]\d{1,2})?\z/

    module_function

    def input(raw)
      # A tela só manda as parcelas: zero é parcela única, à vista (revisão 12).
      mode = raw[:mode].to_s.presence || (raw[:installments].to_i.zero? ? "cash" : "installments")
      raise Refused.new(I18n.t("agreements.refused.mode"), field: "mode") unless Agreement::MODES.include?(mode)

      # Revisão 12: enquanto a pessoa não mexe na entrada, o valor na tela é o inicial, e o servidor o recalcula para os títulos e descontos de agora.
      auto = raw[:down_payment_auto].to_s == "1"
      Simulation::Input.new(bill_ids: Array(raw[:bill_ids]).compact_blank, mode: mode, discounts_bp: discounts(raw[:discounts]), down_payment_cents: auto ? nil : money(raw[:down_payment], "down_payment"),
                            down_payment_on: date(raw[:down_payment_on], "down_payment_on"), installments: raw[:installments].to_s.strip.presence&.to_i, day: raw[:day].to_s.strip.presence&.to_i,
                            replace: raw[:replace].to_s == "1", credit_cents: zero?(raw[:credit]) ? 0 : money(raw[:credit], "credit").to_i, auto_down: auto)
    end

    # { componente => centésimos de ponto }; vazio é zero.
    def discounts(raw)
      Caps::COMPONENTS.to_h do |component|
        text = raw&.[](component).to_s.strip
        next [ component, 0 ] if text.empty?
        raise Refused.new(I18n.t("agreements.refused.discount_invalid"), field: "discounts_#{component}") unless text.match?(PERCENT)

        whole, fraction = text.tr(",", ".").split(".")
        [ component, whole.to_i * 100 + fraction.to_s.ljust(2, "0").to_i ]
      end
    end

    # O crédito a usar nasce em zero (revisão 12), que `Money.parse_cents` recusa por ser valor de pagamento.
    def zero?(text) = text.to_s.strip.match?(/\A0+(,0{1,2})?\z/)

    def money(text, field)
      return nil if text.to_s.strip.empty?

      cents, problem = Money.parse_cents(text)
      raise Refused.new("#{I18n.t("agreements.fields.#{field}")}: #{problem}.", field: field) unless cents

      cents
    end

    def date(text, field)
      return nil if text.to_s.strip.empty?

      Date.iso8601(text.to_s)
    rescue Date::Error
      BrDate.parse(text) || raise(Refused.new(I18n.t("agreements.refused.date_invalid", field: I18n.t("agreements.fields.#{field}")), field: field))
    end
  end
end
