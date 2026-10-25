module Payments
  module Providers
    class Efi
      # Montagem dos corpos e leitura das respostas da Efí, sem rede: dos nossos valores (centavos, datas, pagador) para o formato dela e de volta ao
      # nosso vocabulário. Valores em dinheiro: boleto em centavos inteiros; Pix em texto com duas casas.
      module Payloads
        module_function

        BILLET_STATUS = { "new" => "active", "waiting" => "active", "identified" => "active", "link" => "active", "approved" => "active", "paid" => "paid",
                          "settled" => "paid", "unpaid" => "expired", "canceled" => "canceled", "refunded" => "canceled", "contested" => "active" }.freeze
        PIX_STATUS = { "ATIVA" => "active", "CONCLUIDA" => "paid", "REMOVIDA_PELO_USUARIO_RECEBEDOR" => "canceled", "REMOVIDA_PELO_PSP" => "canceled" }.freeze
        # Juros do Pix: "percentual ao mês (dias corridos)" na tabela do Banco Central; multa: "percentual" (2).
        PIX_INTEREST_MODALITY = 3
        PIX_FINE_MODALITY = 2
        PIX_DISCOUNT_MODALITY = 2

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

        def pix_body(amount_cents:, due_on:, payer:, pix_key:, options:)
          debtor = { "nome" => payer[:name].to_s, person(payer[:document]).to_s => payer[:document] }
          address = (payer[:address] || {}).transform_keys(&:to_s)
          debtor.merge!("logradouro" => [ address["street"], address["number"] ].compact_blank.join(", ").presence, "cidade" => address["city"].presence,
                        "uf" => address["state"].presence, "cep" => address["zip"].presence).compact! if address.values_at("street", "city", "state", "zip").all?(&:present?)
          value = { "original" => decimal(amount_cents) }
          value["multa"] = { "modalidade" => PIX_FINE_MODALITY, "valorPerc" => percent(options[:fine_percent]) } if options[:fine_percent].to_d.positive?
          value["juros"] = { "modalidade" => PIX_INTEREST_MODALITY, "valorPerc" => percent(options[:interest_percent]) } if options[:interest_percent].to_d.positive?
          if options[:discount_percent].to_d.positive?
            value["desconto"] = { "modalidade" => PIX_DISCOUNT_MODALITY, "descontoDataFixa" => [ { "data" => due_on.iso8601, "valorPerc" => percent(options[:discount_percent]) } ] }
          end
          body = { "calendario" => { "dataDeVencimento" => due_on.iso8601, "validadeAposVencimento" => options.fetch(:after_due_days, 30).to_i }, "devedor" => debtor,
                   "valor" => value, "chave" => pix_key }
          body["solicitacaoPagador"] = options[:message].to_s.first(140) if options[:message].present?
          body
        end

        def decimal(cents) = format("%d.%02d", *cents.divmod(100))

        def percent(value) = format("%.2f", value.to_d)

        # "data:image/png;base64,...." -> bytes do PNG; SVG ou qualquer outra coisa -> nil (o QR Code é então gerado aqui).
        def png_from_data_uri(uri)
          match = uri.to_s.match(%r{\Adata:image/png;base64,(?<data>[A-Za-z0-9+/=\s]+)\z})
          return unless match

          bytes = Base64.decode64(match[:data])
          bytes if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
        end

        # Mensagem curta e segura de uma resposta de erro: nunca o corpo inteiro, nunca o que foi enviado.
        def error_message(json)
          return "resposta de erro do fornecedor" unless json.is_a?(Hash)

          description = json["error_description"]
          text = case description
          when Hash then description["message"] || description["property"]
          when String then description
          end
          text ||= [ json["title"], json["detail"] ].compact.join(": ").presence
          violations = Array(json["violacoes"]).filter_map { |item| [ item["propriedade"], item["razao"] ].compact.join(" ") if item.is_a?(Hash) }
          text = [ text, *violations ].compact.join("; ").presence || json["error"] || json["mensagem"]
          text.to_s.gsub(/[[:cntrl:]]/, " ").squish.first(200).presence || "resposta de erro do fornecedor"
        end
      end
    end
  end
end
