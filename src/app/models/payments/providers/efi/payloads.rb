module Payments
  module Providers
    class Efi
      # Montagem dos corpos e leitura das respostas da Efí, sem rede: dos nossos valores (centavos, datas, pagador) para o formato dela e de volta ao
      # nosso vocabulário. Valores em dinheiro: boleto em centavos inteiros; Pix em texto com duas casas.
      module Payloads
        module_function

        BILLET_STATUS = { "new" => "active", "waiting" => "active", "identified" => "active", "link" => "active", "approved" => "active", "paid" => "paid",
                          "settled" => "paid", "unpaid" => "expired", "canceled" => "canceled", "refunded" => "canceled", "contested" => "active" }.freeze
        PIX_STATUS = PixBcb::STATUS

        def person(document)
          document.to_s.length == 14 ? :cnpj : :cpf
        end

        # Endereço completo ou nada: a Efí exige todos os campos juntos.
        def billet_address(address)
          address = (address || {}).transform_keys(&:to_s)
          fields = { "street" => address["street"], "number" => address["number"], "neighborhood" => address["district"], "zipcode" => address["zip"],
                     "city" => address["city"], "state" => address["state"] }
          return nil unless fields.values.all?(&:present?)

          fields.merge("complement" => address["complement"].presence).compact
        end

        def billet_body(custom_id:, amount_cents:, due_on:, payer:, options:)
          customer = if person(payer[:document]) == :cnpj
            { "juridical_person" => { "corporate_name" => payer[:name].to_s, "cnpj" => payer[:document] } }
          else
            { "name" => payer[:name].to_s, "cpf" => payer[:document] }
          end
          address = billet_address(payer[:address])
          customer["address"] = address if address
          billet = { "customer" => customer, "expire_at" => due_on.iso8601 }
          configurations = billet_configurations(options)
          billet["configurations"] = configurations unless configurations.empty?
          billet["message"] = options[:message].to_s.first(400) if options[:message].present?
          billet["conditional_discount"] = { "type" => "percentage", "value" => (options[:discount_percent].to_d * 100).round, "until_date" => due_on.iso8601 } if options[:discount_percent].to_d.positive?
          metadata = { "custom_id" => custom_id }
          metadata["notification_url"] = options[:notification_url] if options[:notification_url].present?
          { "items" => [ { "name" => options[:description].presence || "Cobrança", "value" => amount_cents, "amount" => 1 } ], "metadata" => metadata,
            "payment" => { "banking_billet" => billet } }
        end

        # Multa e juros em centésimos de ponto percentual (200 = 2%); `days_to_write_off`: até quando o boleto vencido ainda paga (0 a 120).
        def billet_configurations(options)
          configurations = {}
          configurations["days_to_write_off"] = options[:write_off_days].to_i if options[:write_off_days]
          configurations["fine"] = (options[:fine_percent].to_d * 100).round if options[:fine_percent].to_d.positive?
          configurations["interest"] = { "value" => (options[:interest_percent].to_d * 100).round, "type" => "monthly" } if options[:interest_percent].to_d.positive?
          configurations
        end

        # Cobrança de cartão em um passo (R278): só o `payment_token` e as parcelas; nunca dado de cartão. Cliente (nome, documento, e-mail e telefone, se houver)
        # e endereço de cobrança completo (ou nenhum): a obrigatoriedade na Efí fica no roteiro de homologação.
        def card_body(custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil)
          customer = if person(payer[:document]) == :cnpj
            { "juridical_person" => { "corporate_name" => payer[:name].to_s, "cnpj" => payer[:document] } }
          else
            { "name" => payer[:name].to_s, "cpf" => payer[:document] }
          end
          customer["email"] = payer[:email] if payer[:email].present?
          customer["phone_number"] = payer[:phone].to_s.gsub(/\D/, "") if payer[:phone].to_s.gsub(/\D/, "").length.in?(10..11)
          card = { "installments" => installments.to_i, "payment_token" => payment_token, "customer" => customer }
          address = billet_address(payer[:address])
          card["billing_address"] = address if address
          metadata = { "custom_id" => custom_id }
          metadata["notification_url"] = notification_url if notification_url.present?
          { "items" => [ { "name" => description.presence || "Cobrança", "value" => amount_cents, "amount" => 1 } ], "metadata" => metadata,
            "payment" => { "credit_card" => card } }
        end

        # Resposta da cobrança de cartão no nosso vocabulário. `approved`: aprovado pelo emissor, a confirmar; `unpaid` (ou qualquer `refusal`): recusado.
        def card_result(data, fallback_installments: 1)
          refusal = data["refusal"].is_a?(Hash) ? data["refusal"] : {}
          declined = data["status"].to_s == "unpaid" || refusal["reason"].present?
          status = declined ? "declined" : (data["status"].to_s == "paid" ? "paid" : "approved")
          Providers::CardResult.new(external_id: (data["charge_id"] || data["id"]).to_s.presence, status: status, amount_cents: data["total"], installments: (data["installments"] || fallback_installments).to_i,
                                    refusal_code: (refusal_code(refusal["reason"]) if declined), retry: declined && refusal["retry"] == true,
                                    refusal_reason: (refusal["reason"].to_s.gsub(/[[:cntrl:]]/, " ").squish.first(200).presence if declined))
        end

        # Classifica o motivo da recusa (o texto do fornecedor não vai para a tela do cliente).
        def refusal_code(reason)
          case reason.to_s
          when /invalid|inv[aá]lid/i then "invalid_data"
          when /security|seguran/i then "security"
          when /try again|later|novamente|mais tarde|indispon/i then "try_later"
          else "other"
          end
        end

        # O corpo da `cobv` é o do padrão do Banco Central (`PixBcb`, comum aos adaptadores de Pix).
        def pix_body(amount_cents:, due_on:, payer:, pix_key:, options:) = PixBcb.cobv_body(amount_cents: amount_cents, due_on: due_on, payer: payer, pix_key: pix_key, options: options)

        def decimal(cents) = PixBcb.decimal(cents)

        def percent(value) = PixBcb.percent(value)

        # "data:image/png;base64,...." -> bytes do PNG; SVG ou qualquer outra coisa -> nil (o QR Code é então gerado aqui).
        def png_from_data_uri(uri)
          match = uri.to_s.match(%r{\Adata:image/png;base64,(?<data>[A-Za-z0-9+/=\s]+)\z})
          return unless match

          bytes = Base64.decode64(match[:data])
          bytes if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
        end

        # Mensagem curta e segura de uma resposta de erro (RFC 7807 do Pix ou o formato das cobranças da Efí).
        def error_message(json) = PixBcb.error_message(json)
      end
    end
  end
end
