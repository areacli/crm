module Agreements
  # Termo do acordo (11, R219, R219a, DA14): o texto-modelo do CRM com os dados do credor e do cliente, os títulos com a base por componente, os descontos, a
  # entrada e as parcelas, a taxa efetiva anual, a soma total a pagar e o total dos juros do parcelamento (CDC, art. 52), o aviso do título de estorno (R233)
  # e as políticas congeladas que afetam o cliente (R210), com destaque para a forma da quebra e a mora (CDC, art. 54, § 4º). O resultado é um hash
  # de textos e números prontos (chaves em texto): a tela o mostra, e o aceite o guarda como estava, sem edição (R220). O credor sem CNPJ ou razão social
  # não tem rascunho (`missing` diz o que falta).
  module Term
    # As políticas congeladas que afetam o cliente (R210); as de crédito (quem aceita, crédito entre contratos) não entram.
    CUSTOMER_POLICIES = %w[effectuation cash_effectuation break_form late_charges tolerance_agreement minimum_to_break late_down_payment bank_reversal first_period early_payment
                           early_settlement reactivation original_paid_before partial_down_payment installment_number_before_effectuation fees credit_reversal_origin].freeze

    module_function

    def build(agreement)
      tenant = agreement.tenant
      terms = agreement.terms
      missing = []
      missing << "CNPJ" if tenant.cnpj.blank?
      missing << "razão social" if tenant.legal_name.blank?
      bills = agreement.agreement_bills.includes(:bill, :contract).sort_by { |item| [ item.bill.due_date, item.bill_id ] }
      contracts = bills.map(&:contract).uniq
      addressees = Parties.financial_responsibles(contracts)
      {
        "number" => agreement.number, "built_on" => agreement.built_on.iso8601, "valid_until" => agreement.valid_until.iso8601,
        "missing" => missing,
        "creditor" => { "legal_name" => tenant.legal_name, "trade_name" => tenant.trade_name, "cnpj" => (Document.format(tenant.cnpj) if tenant.cnpj.present?), "address" => address_of(tenant) },
        "customer" => { "name" => agreement.customer.name, "document" => agreement.customer.formatted_document },
        "addressees" => addressees.map { |customer| { "name" => customer.name, "document" => customer.formatted_document } },
        "mode" => agreement.mode,
        "bills" => bills.map { |item| { "number" => item.bill.number, "contract" => item.contract.label, "due" => item.bill.due_date.iso8601, "base" => item.base, "discount" => item.discount, "value_cents" => item.value_cents } },
        "base_cents" => agreement.base_cents, "discount_cents" => agreement.discount_cents, "value_cents" => agreement.value_cents, "credit_cents" => agreement.credit_cents, "net_cents" => agreement.net_cents,
        "discounts_bp" => agreement.discounts_bp,
        "schedule" => agreement.schedule, "method" => agreement.installment_method, "rate_pct" => agreement.rate_pct.to_s("F"), "effective_annual_pct" => agreement.effective_annual_pct.to_s("F"),
        "total_cents" => agreement.total_cents, "interest_cents" => agreement.interest_cents,
        "variables" => { "break_days" => terms.dig("segment", "break_days"), "tolerance_days" => terms.dig("segment", "tolerance_days"), "down_payment_days" => terms.dig("segment", "down_payment_days") },
        "late" => late_of(terms),
        "policies" => policy_lines(terms),
        "warnings" => terms["warnings"].to_a
      }
    end

    def address_of(tenant)
      parts = [ [ tenant.street, tenant.number ].compact_blank.join(", "), tenant.complement, tenant.district, [ tenant.city, tenant.state ].compact_blank.join("/"), (tenant.zip if tenant.zip.present?) ]
      parts.compact_blank.join(" · ").presence
    end

    # A mora do título de acordo (R228): multa, juros e convenção, pelos parâmetros congelados.
    def late_of(terms)
      rule = terms.dig("parameters", "late_rule") or return nil
      { "fine_pct" => rule["fine"].to_f * 100, "interest_pct" => rule["rate"].to_f * 100, "form" => rule["form"], "convention" => rule["convention"], "index" => rule["index"], "fees_pct" => rule["fees"].to_f * 100,
        "applies" => terms.dig("policies", "late_charges") != "none" }
    end

    def policy_lines(terms)
      policies = terms["policies"].to_h
      CUSTOMER_POLICIES.filter_map do |key|
        value = policies[key] or next
        { "key" => key, "title" => I18n.t("agreements.policies.#{key}.title"), "text" => policy_text(key, value) }
      end
    end

    def policy_text(key, value)
      return I18n.t("agreements.policies.#{key}.options.#{value}") unless value.is_a?(Hash)

      case value["kind"]
      when "percent" then "#{format('%.2f', value['value'] / 100.0).tr('.', ',')}% do devido"
      when "tolerance" then I18n.t("agreements.policies.minimum_to_break.options.tolerance")
      else value["value"].zero? ? "nenhum" : "R$ #{Money.format(value['value'])}"
      end
    end
  end
end
