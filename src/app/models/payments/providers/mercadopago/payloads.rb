module Payments
  module Providers
    class Mercadopago
      # Corpos e leituras da API Orders do Mercado Pago (12, revisão 6). Fonte: a documentação lida em 14/11/2026. Onde as páginas se contradizem, o código
      # segue o exemplo e diz no comentário; cada contradição é item do roteiro de homologação (docs/homologacao-mercadopago.md).
      module Payloads
        module_function

        # Recusas do cartão pelo `status_detail` (a lista da API Orders remete a uma página não lida; os nomes da API de pagamentos, `cc_rejected_*`,
        # servem de base). Nossa classificação e se tentar de novo pode dar certo.
        REFUSALS = [ [ /bad_filled|invalid/, "invalid_data", true ], [ /high_risk|blacklist|fraud/, "security", false ],
                     [ /insufficient_amount/, "other", true ], [ /3ds|call_for_authorize|duplicated|max_attempts|card_disabled/, "other", false ] ].freeze

        def digits(value) = value.to_s.gsub(/\D/, "")

        def money(cents) = format("%.2f", cents.to_i / 100.0)

        def cents(value) = value.nil? ? nil : (BigDecimal(value.to_s) * 100).round.to_i

        # Pix e boleto exigem e-mail e documento; o boleto exige o endereço completo (página do boleto na API Orders).
        def payer(payer, address: false)
          document = digits(payer[:document])
          name = payer[:name].to_s.strip
          result = { "email" => payer[:email].to_s, "first_name" => name.split.first.to_s.first(60), "last_name" => name.split.drop(1).join(" ").first(60).presence || name.first(60),
                     "identification" => { "type" => document.length == 14 ? "CNPJ" : "CPF", "number" => document } }
          result["address"] = address(payer) if address
          result
        end

        def address(payer)
          data = (payer[:address] || {}).to_h.stringify_keys
          zip = digits(data["zip"])
          required = [ data["street"], data["district"], data["city"], data["state"], (zip if zip.length == 8) ]
          raise Error, I18n.t("payments.providers.mercadopago.errors.payer_address") if required.any?(&:blank?)

          # O número vai como "N/A" quando não há (o exemplo da API Orders; a página de pagamentos usa "S/N": item do roteiro).
          { "zip_code" => zip, "street_name" => data["street"].to_s.first(120), "street_number" => (data["number"].presence || "N/A").to_s.first(20),
            "neighborhood" => data["district"].to_s.first(60), "city" => data["city"].to_s.first(60), "state" => data["state"].to_s.upcase.first(2) }
        end

        # Pix imediato com validade até 23h59min59s do vencimento, em duração ISO 8601 a partir de agora (de 30 minutos a 30 dias, R284q, R284y).
        def pix_duration(due_on, now: Time.current)
          ends = Time.find_zone("America/Sao_Paulo").local(due_on.year, due_on.month, due_on.day, 23, 59, 59)
          seconds = (ends - now).to_i.clamp(30 * 60, 30 * 86_400)
          days, rest = seconds.divmod(86_400)
          hours, rest = rest.divmod(3600)
          minutes = rest / 60
          "P#{days}DT#{hours}H#{minutes}M"
        end

        # Boleto: dias a partir da emissão (de 1 a 30). O Mercado Pago passa o fim de semana ao dia útil seguinte (R284z).
        def boleto_duration(due_on, today: Date.current) = "P#{(due_on - today).to_i.clamp(1, 30)}D"

        def order(custom_id:, amount_cents:, payer:, method:, description: nil)
          { "type" => "online", "processing_mode" => "automatic", "external_reference" => reference(custom_id), "total_amount" => money(amount_cents),
            "description" => (description.presence || "Cobrança").to_s.first(150), "payer" => payer,
            "transactions" => { "payments" => [ { "amount" => money(amount_cents) }.merge(method) ] } }
        end

        # `external_reference`: até 64 caracteres, letras, números, "-" e "_".
        def reference(custom_id) = custom_id.to_s.gsub(/[^A-Za-z0-9_-]/, "").first(64)

        def pix_order(custom_id:, amount_cents:, due_on:, payer:, description: nil)
          order(custom_id: custom_id, amount_cents: amount_cents, payer: payer(payer), description: description,
                method: { "payment_method" => { "id" => "pix", "type" => "bank_transfer" }, "expiration_time" => pix_duration(due_on) })
        end

        def boleto_order(custom_id:, amount_cents:, due_on:, payer:, description: nil)
          order(custom_id: custom_id, amount_cents: amount_cents, payer: payer(payer, address: true), description: description,
                method: { "payment_method" => { "id" => "boleto", "type" => "ticket" }, "expiration_time" => boleto_duration(due_on) })
        end

        # Cartão: o token dos campos do Mercado Pago, a bandeira (o `id` do meio, que o Mercado Pago deu no navegador) e as parcelas. Sem 3DS (MPG5).
        def card_order(custom_id:, amount_cents:, installments:, token:, brand:, payer:, description: nil)
          order(custom_id: custom_id, amount_cents: amount_cents, payer: { "email" => payer[:email].to_s }, description: description,
                method: { "payment_method" => { "id" => brand.to_s, "type" => "credit_card", "token" => token.to_s, "installments" => installments.to_i } })
        end

        # ---- Leitura ----

        def payment(order) = Array(order.dig("transactions", "payments")).first || {}

        def method_data(order) = payment(order)["payment_method"] || {}

        def refunded_cents(order) = Array(order.dig("transactions", "refunds")).sum { |refund| cents(refund["amount"]).to_i }

        # Estado nosso. `processed` é pago; `refunded`, pago com devolução (a devolução é outro fato); `action_required`, `created` e `processing`, à espera.
        def status_of(order)
          case order["status"].to_s
          when "processed", "refunded", "partially_refunded" then "paid"
          when "canceled" then "canceled"
          when "expired" then "expired"
          when "failed" then "failed"
          else "active"
          end
        end

        # O pago entra pelo valor da transação, o que o CRM cobrou: os juros do parcelamento do comprador são da operadora (R284v).
        def paid_cents(order) = status_of(order) == "paid" ? cents(payment(order)["amount"] || order["total_amount"]) : nil

        def card_result(order, fallback_installments:)
          id = order["id"].presence
          installments = method_data(order)["installments"] || fallback_installments
          case order["status"].to_s
          when "processed" then CardResult.new(external_id: id, status: "paid", amount_cents: paid_cents(order), installments: installments)
          when "processing", "action_required", "created" then CardResult.new(external_id: id, status: "in_analysis", amount_cents: cents(order["total_amount"]), installments: installments)
          else
            detail = [ payment(order)["status_detail"], order["status_detail"] ].compact.join(" ")
            _pattern, code, retry_flag = REFUSALS.find { |pattern, _, _| detail.match?(pattern) } || [ nil, "other", false ]
            CardResult.new(external_id: id, status: "declined", installments: installments, refusal_code: code, retry: retry_flag, refusal_reason: detail.first(200).presence)
          end
        end

        # Parcelas da API de meios de pagamento pelo `payment_method_id` (a bandeira), sem o BIN (MPG13). Juros quando a taxa da parcela é maior que zero.
        def installment_options(data)
          Array(data).flat_map { |entry| Array(entry["payer_costs"]) }.filter_map do |cost|
            count = cost["installments"].to_i
            next unless count.positive?

            InstallmentOption.new(installments: count, installment_cents: cents(cost["installment_amount"]).to_i, total_cents: cents(cost["total_amount"]).to_i,
                                  has_interest: cost["installment_rate"].to_f.positive?)
          end.uniq(&:installments)
        end

        # O mesmo identificador para o aviso e para a lista de pagos (R284b): o pedido e o estado, sem o "order." da ação.
        def event_id(order_id, status) = "#{order_id}:#{status.to_s.delete_prefix('order.')}"

        def kind_of(status)
          case status.to_s.delete_prefix("order.")
          when "processed" then :paid
          when "refunded", "partially_refunded" then :refunded
          when "canceled" then :canceled
          when "expired" then :expired
          else :other
          end
        end

        def error_message(json)
          return unless json.is_a?(Hash)

          errors = Array(json["errors"]).map { |error| [ error["code"], error["message"] || error["details"] ].compact.join(" ") }
          (errors.presence || [ json["message"], json["error"] ].compact).join("; ").first(300).presence
        end

        def error_code(json) = json.is_a?(Hash) ? (Array(json["errors"]).first&.dig("code") || json["error"]).to_s : ""

        # A ficha de compensação gerada aqui (R284e, R284z): o banco vem da linha digitável e do `financial_institution`; o beneficiário, da integração.
        def slip_attributes(account, order, instrument, due_on)
          config = account.config
          data = method_data(order)
          address = (instrument&.payer_address || {}).transform_keys(&:to_s)
          line = data["digitable_line"].to_s
          { bank_name: data["financial_institution"].to_s.presence || "Banco #{line[0, 3]}", bank_code: line[0, 3], digitable_line: line, due_on: due_on,
            amount_cents: instrument&.amount_cents || cents(order["total_amount"]), beneficiary_name: config["beneficiary_name"].to_s,
            beneficiary_document: digits(config["beneficiary_document"]), agency_code: "—", wallet_our_number: data["reference"].to_s.presence || "—",
            document_number: instrument&.custom_id.to_s.last(15), species: "DM", issued_on: (instrument&.issued_at || Time.current).to_date,
            payer_name: instrument&.payer_name.to_s, payer_document: instrument&.payer_document.to_s,
            payer_address: [ [ address["street"], address["number"], address["complement"] ].compact_blank.join(", "),
                             [ address["district"], address["city"], address["state"] ].compact_blank.join(" - "), address["zip"] ].compact_blank.join(" | "),
            payment_place: "Pagável em qualquer banco até o vencimento", instructions: [ "Não receber após o vencimento." ] }
        end
      end
    end
  end
end
