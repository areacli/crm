module Agreements
  # Lê o formulário da simulação (11, R211 a R213): títulos, à vista ou parcelado, o desconto por componente em percentual (vírgula ou ponto, até duas casas),
  # a entrada (valor e vencimento), as parcelas e o dia de vencimento. Valor ilegível levanta Refused com o campo, e o formulário volta com a mensagem.
  module FormParams
    PERCENT = /\A\d{1,3}(?:[.,]\d{1,2})?\z/

    module_function

    def input(raw)
      mode = raw[:mode].to_s
      raise Refused.new(I18n.t("agreements.refused.mode"), field: "mode") unless Agreement::MODES.include?(mode)

      Simulation::Input.new(bill_ids: Array(raw[:bill_ids]).compact_blank, mode: mode, discounts_bp: discounts(raw[:discounts]), down_payment_cents: money(raw[:down_payment], "down_payment"),
                            down_payment_on: date(raw[:down_payment_on], "down_payment_on"), installments: raw[:installments].to_s.strip.presence&.to_i, day: raw[:day].to_s.strip.presence&.to_i,
                            replace: raw[:replace].to_s == "1", credit_cents: money(raw[:credit], "credit").to_i)
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
