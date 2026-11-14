module Payments
  module Providers
    class Pagbank
      # Corpos e leituras da API Order do PagBank (12, revisão 5). Fonte: o portal do PagBank lido em 14/11/2026. Onde as páginas se contradizem, o código
      # segue o exemplo e diz no comentário; cada contradição é item do roteiro de homologação (docs/homologacao-pagbank.md).
      module Payloads
        module_function

        UF_NAMES = { "AC" => "Acre", "AL" => "Alagoas", "AP" => "Amapá", "AM" => "Amazonas", "BA" => "Bahia", "CE" => "Ceará", "DF" => "Distrito Federal",
                     "ES" => "Espírito Santo", "GO" => "Goiás", "MA" => "Maranhão", "MT" => "Mato Grosso", "MS" => "Mato Grosso do Sul", "MG" => "Minas Gerais",
                     "PA" => "Pará", "PB" => "Paraíba", "PR" => "Paraná", "PE" => "Pernambuco", "PI" => "Piauí", "RJ" => "Rio de Janeiro", "RN" => "Rio Grande do Norte",
                     "RS" => "Rio Grande do Sul", "RO" => "Rondônia", "RR" => "Roraima", "SC" => "Santa Catarina", "SP" => "São Paulo", "SE" => "Sergipe",
                     "TO" => "Tocantins" }.freeze
        # Valor mínimo do boleto (página do boleto).
        BOLETO_MIN_CENTS = 20
        # Códigos de recusa do cartão (página "motivos de compra negada"): os "retentáveis" e a classificação nossa (CardResult).
        RETRYABLE_REFUSALS = %w[10000 10002 20001 20003].freeze
        REFUSAL_CODES = { "10000" => "security", "10002" => "try_later", "10003" => "invalid_data", "20007" => "invalid_data", "20008" => "invalid_data" }.freeze

        def digits(value) = value.to_s.gsub(/\D/, "")

        def customer(payer, email: nil)
          { "name" => payer[:name].to_s.strip.first(120), "tax_id" => digits(payer[:document]), "email" => email.presence }.compact
        end

        def item(custom_id, amount_cents, description)
          { "reference_id" => custom_id.to_s.first(64), "name" => (description.presence || "Cobrança").to_s.first(100), "quantity" => 1, "unit_amount" => amount_cents.to_i }
        end

        # Pix imediato com validade (R284q): o QR Code vale até 23h59min59s do vencimento, na hora de Brasília. O pedido vai pelo `qr_codes[]` do objeto do
        # pedido (o guia do Pix de setembro de 2026 põe o Pix numa cobrança, `charges[].payment_method.pix`, e a OpenAPI não tem nenhum dos dois): é a forma
        # que a página do objeto e a de avisos mostram. A leitura aceita as duas.
        def pix_order(custom_id:, amount_cents:, due_on:, payer:, notification_url:, description: nil)
          { "reference_id" => custom_id.to_s.first(64), "customer" => customer(payer), "items" => [ item(custom_id, amount_cents, description) ],
            "qr_codes" => [ { "amount" => { "value" => amount_cents.to_i }, "expiration_date" => "#{due_on.iso8601}T23:59:59-03:00" } ],
            "notification_urls" => [ notification_url ].compact }
        end

        # Boleto no modelo `cobranca` quando há multa, juros ou desconto (percentual vezes 100; multa e juros a partir do dia seguinte ao vencimento);
        # senão, no padrão (`proposta`). A página escreve o modelo como `cobranca` no exemplo e `COBRANCA` no texto: vai o do exemplo.
        def boleto_order(custom_id:, amount_cents:, due_on:, payer:, options:, notification_url:)
          instructions = payment_instructions(due_on, options)
          lines = options[:message].to_s.squish.scan(/.{1,75}(?:\s|\z)/).map(&:strip).reject(&:empty?)
          boleto = { "due_date" => due_on.iso8601, "days_until_expiration" => options[:write_off_days].to_i.to_s, "holder" => boleto_holder(payer),
                     "instruction_lines" => ({ "line_1" => lines[0], "line_2" => lines[1] }.compact.presence), "template" => ("cobranca" if instructions) }.compact
          charge = { "reference_id" => custom_id.to_s.first(64), "description" => (options[:description].presence || "Cobrança").to_s.first(64),
                     "amount" => { "value" => amount_cents.to_i, "currency" => "BRL" }, "payment_method" => { "type" => "BOLETO", "boleto" => boleto },
                     "payment_instructions" => instructions }.compact
          { "reference_id" => custom_id.to_s.first(64), "customer" => customer(payer), "items" => [ item(custom_id, amount_cents, options[:description]) ],
            "charges" => [ charge ], "notification_urls" => [ notification_url ].compact }
        end

        def payment_instructions(due_on, options)
          fine = percent(options[:fine_percent], 9999)
          interest = percent(options[:interest_percent], 5999)
          discount = percent(options[:discount_percent], 9999)
          after = (due_on + 1).iso8601
          result = { "fine" => ({ "date" => after, "value" => fine } if fine), "interest" => ({ "date" => after, "value" => interest } if interest),
                     "discounts" => ([ { "due_date" => due_on.iso8601, "value" => discount } ] if discount) }.compact
          result.presence
        end

        # Percentual em "vezes 100" (2,00% = 200), dentro do limite da página; zero ou vazio não vai.
        def percent(value, max)
          number = value.to_f
          number.positive? ? [ (number * 100).round, max ].min : nil
        end

        # O PagBank exige o endereço completo do pagador no boleto (página do boleto): sem ele, o boleto falha aqui, sem chamada (R274; plano, PB11).
        def boleto_holder(payer)
          address = (payer[:address] || {}).to_h.stringify_keys
          uf = address["state"].to_s.upcase
          zip = digits(address["zip"])
          required = [ address["street"], address["district"], address["city"], UF_NAMES[uf], (zip if zip.length == 8) ]
          raise Error, I18n.t("payments.providers.pagbank.errors.payer_address") if required.any?(&:blank?)

          { "name" => payer[:name].to_s.strip.first(120), "tax_id" => digits(payer[:document]),
            "address" => { "street" => address["street"].to_s.first(160), "number" => (address["number"].presence || "S/N").to_s.first(20),
                           "complement" => address["complement"].presence&.first(40), "locality" => address["district"].to_s.first(60), "city" => address["city"].to_s.first(90),
                           "region" => UF_NAMES.fetch(uf), "region_code" => uf, "country" => "BRA", "postal_code" => zip }.compact }
        end

        # Cartão cifrado no navegador pelo SDK do PagBank (R284t): só o `encrypted` vai, com `store` falso (nada guardado no PagBank). Juros do comprador
        # (acima das parcelas sem juros): o total com juros em `amount.value` e os juros em `amount.fees.buyer.interest` (página de taxas).
        def card_order(custom_id:, amount_cents:, installments:, encrypted:, payer:, description:, notification_url:, interest_cents: 0, soft_descriptor: nil)
          amount = { "value" => amount_cents.to_i + interest_cents.to_i, "currency" => "BRL" }
          amount["fees"] = { "buyer" => { "interest" => { "total" => interest_cents.to_i, "installments" => installments.to_i } } } if interest_cents.to_i.positive?
          method = { "type" => "CREDIT_CARD", "installments" => installments.to_i, "capture" => true, "soft_descriptor" => soft_descriptor.presence,
                     "card" => { "encrypted" => encrypted.to_s, "store" => false }, "holder" => { "name" => payer[:name].to_s.strip.first(120), "tax_id" => digits(payer[:document]) } }.compact
          { "reference_id" => custom_id.to_s.first(64), "customer" => customer(payer, email: payer[:email]), "items" => [ item(custom_id, amount_cents, description) ],
            "charges" => [ { "reference_id" => custom_id.to_s.first(64), "description" => (description.presence || "Cobrança").to_s.first(64), "amount" => amount, "payment_method" => method } ],
            "notification_urls" => [ notification_url ].compact }
        end

        # ---- Leitura ----

        def charge(order) = Array(order["charges"]).first || {}

        def summary(charge) = charge.dig("amount", "summary") || {}

        def buyer_interest(charge) = charge.dig("amount", "fees", "buyer", "interest", "total").to_i

        # O que o fornecedor diz ter sido pago, sem os juros do parcelamento, que são da operadora (R284v).
        def paid_cents(charge)
          paid = summary(charge)["paid"]
          paid.nil? ? nil : [ paid.to_i - buyer_interest(charge), 0 ].max
        end

        def refunded_cents(charge) = summary(charge)["refunded"].to_i

        def copy_paste(order) = Array(order["qr_codes"]).first&.dig("text").presence || charge(order).dig("qr_code", "text").presence

        def qr_expires_at(order)
          value = Array(order["qr_codes"]).first&.dig("expiration_date") || charge(order).dig("payment_method", "pix", "expiration_date")
          Time.iso8601(value.to_s) if value.present?
        rescue ArgumentError
          nil
        end

        # Estado nosso de um pedido de boleto ou Pix. `CANCELED` sem pagamento é o que o PagBank faz com o não pago na validade (boleto e Pix).
        def status_of(order, kind, now: Time.current)
          current = charge(order)
          case current["status"].to_s
          when "PAID" then "paid"
          when "CANCELED" then refunded_cents(current).positive? ? "paid" : "expired"
          when "DECLINED" then "failed"
          when "WAITING", "AUTHORIZED", "IN_ANALYSIS" then "active"
          else
            kind == "pix" && (expires = qr_expires_at(order)) && expires <= now ? "expired" : "active"
          end
        end

        def boleto_line(order)
          boleto = charge(order).dig("payment_method", "boleto") || {}
          boleto["formatted_barcode"].presence || boleto["barcode"].presence
        end

        def boleto_due(order)
          value = charge(order).dig("payment_method", "boleto", "due_date")
          Date.iso8601(value.to_s) if value.present?
        rescue Date::Error
          nil
        end

        def pdf_link(order)
          Array(charge(order)["links"]).find { |link| link["media"].to_s.include?("pdf") || link["href"].to_s.end_with?(".pdf") }&.dig("href")
        end

        def card_result(order, fallback_installments:)
          current = charge(order)
          status = current["status"].to_s
          installments = current.dig("payment_method", "installments") || fallback_installments
          id = order["id"].presence
          case status
          when "PAID" then CardResult.new(external_id: id, status: "paid", amount_cents: paid_cents(current), installments: installments)
          when "AUTHORIZED" then CardResult.new(external_id: id, status: "approved", amount_cents: current.dig("amount", "value"), installments: installments)
          when "IN_ANALYSIS" then CardResult.new(external_id: id, status: "in_analysis", amount_cents: current.dig("amount", "value"), installments: installments)
          else
            code = current.dig("payment_response", "code").to_s
            CardResult.new(external_id: id, status: "declined", installments: installments, refusal_code: REFUSAL_CODES.fetch(code, "other"),
                           retry: RETRYABLE_REFUSALS.include?(code), refusal_reason: [ code.presence, current.dig("payment_response", "message") ].compact.join(" ").first(200).presence)
          end
        end

        # Parcelas da API de taxas: as da bandeira pedida. A página diz que a resposta vem "por bandeira"; a busca aceita a bandeira em qualquer nível de
        # `payment_methods.credit_card`, porque o exemplo não deixa claro o aninhamento (item do roteiro).
        def installment_plans(data, brand)
          cards = data.dig("payment_methods", "credit_card") || {}
          plans = cards.is_a?(Hash) ? cards.find { |name, _| name.to_s.downcase == brand.to_s.downcase }&.last : nil
          plans = plans["installment_plans"] if plans.is_a?(Hash)
          Array(plans).filter_map do |plan|
            count = plan["installments"].to_i
            next unless count.positive?

            total = plan.dig("amount", "value").to_i
            InstallmentOption.new(installments: count, installment_cents: plan["installment_value"].to_i, total_cents: total, has_interest: plan["interest_free"] != true)
          end
        end

        # O aviso do PagBank é o pedido inteiro, sem identificador de evento (página de avisos): o identificador é montado do pedido, da cobrança, do estado
        # e dos valores, e um aviso repetido com o mesmo estado é o mesmo evento. Nada do pagador nem do cartão é lido.
        def notification(order)
          current = charge(order)
          status = current["status"].to_s.presence || (Array(order["qr_codes"]).any? ? "QR" : "ORDER")
          paid = summary(current)["paid"].to_i
          refunded = refunded_cents(current)
          kind = case status
          when "PAID" then refunded.positive? ? :refunded : :paid
          when "CANCELED" then refunded.positive? ? :refunded : :canceled
          else :other
          end
          paid_at = current["paid_at"].presence
          Notification.new(event_id: [ order["id"], current["id"] || "-", status, paid, refunded ].join(":").first(200), kind: kind, external_id: order["id"],
                           amount_cents: (paid_cents(current) if paid.positive?), occurred_at: (PixBcb.time_of(paid_at) if paid_at),
                           end_to_end_id: current.dig("payment_method", "pix", "end_to_end_id").presence, custom_id: order["reference_id"].presence,
                           current_status: status)
        end

        def error_message(json)
          errors = Array(json.is_a?(Hash) ? json["error_messages"] : nil)
          errors.map { |error| [ error["code"], error["description"] || error["error"], error["parameter_name"] ].compact.join(" ") }.join("; ").first(300).presence
        end

        def error_codes(json) = Array(json.is_a?(Hash) ? json["error_messages"] : nil).map { |error| error["code"].to_s }
      end
    end
  end
end
