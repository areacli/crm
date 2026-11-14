module Payments
  module Providers
    # Mercado Pago, o quarto fornecedor real (12, revisão 6; plano do adaptador, decisões MPG1 a MPG13, pela recomendação). Fonte: a documentação de
    # desenvolvedores lida em 14/11/2026; o que ela não diz ou contradiz é item do roteiro de homologação (docs/homologacao-mercadopago.md).
    #
    # API Orders (`/v1/orders`, MPG1); o identificador externo é o do pedido. Credencial pela conexão por autorização (OAuth, MPG2). Boleto sem PDF no
    # Mercado Pago: a ficha é desenhada aqui da linha digitável (MPG4), e o boleto sai da página no vencimento, porque o pago depois é devolvido (MPG8).
    # Pix imediato com validade até o fim do vencimento; QR Code gerado aqui. Cartão em campos do próprio Mercado Pago na página, sem 3DS (MPG5, MPG6).
    # Aviso por aplicação, numa rota por fornecedor, conferido pela assinatura com o segredo do webhook da aplicação (MPG3). Lista de pagos pela busca de
    # pedidos (MPG11). Idempotência documentada: tudo repete com o nosso identificador (MPG12). O cliente HTTP é injetável (`Mercadopago.http_client=`):
    # nenhum teste chama o Mercado Pago. Tokens e dados do pagador nunca vão a log.
    class Mercadopago < Base
      include Boleto
      include Pix
      include Card
      include Authorization

      SDK_URL = "https://sdk.mercadopago.com/js/v2".freeze

      MANIFEST = Manifest.new(
        provider: "mercadopago",
        modalities: %w[boleto pix card],
        fields: [
          # A ficha do boleto é desenhada aqui e imprime o beneficiário como o Mercado Pago o tem (a confirmar na homologação).
          Manifest::Field.new(name: "beneficiary_name", type: :text, modalities: %w[boleto], required: true, maxlength: 100),
          Manifest::Field.new(name: "beneficiary_document", type: :text, modalities: %w[boleto], required: true, maxlength: 18),
          Manifest::Field.new(name: "expire_days", type: :number, modalities: %w[boleto pix], min: 1, max: 30, default: 3),
          Manifest::Field.new(name: "max_installments", type: :number, modalities: %w[card], min: 1, max: 12, default: 1)
        ],
        capabilities: { credentials: "authorization", webhook: "provider", webhook_auth: %w[signature], pdf: "generated", qr: "text", batch_limit: nil,
                        repeatable_issue: %w[boleto pix], due_date_change: false, max_due_days: 30, boleto_after_due: false, payer_email_required: true,
                        paid_list: { "pix" => { every: 10 }, "boleto" => { every: 60 }, "card" => { every: 60 } },
                        card_checkout: { driver: "payments/drivers/mercadopago", script: nil, fields: "provider" } }
      )

      API = "https://api.mercadopago.com".freeze
      AUTH = "https://auth.mercadopago.com/authorization".freeze
      # Domínios que o SDK v2 cita (lido no arquivo em 14/11/2026): o próprio SDK, os quadros dos campos, a API e os estáticos. A lista do que ele chama de
      # fato é item do roteiro, medida no console do navegador.
      CARD_HOSTS = { script: %w[https://sdk.mercadopago.com https://http2.mlstatic.com], frame: %w[https://secure-fields.mercadopago.com https://api-static.mercadopago.com],
                     connect: %w[https://api.mercadopago.com https://api-static.mercadopago.com https://api.mercadolibre.com https://http2.mlstatic.com],
                     img: %w[https://http2.mlstatic.com] }.freeze
      PROBE_ORDER = "ORD00000000000000000000000000".freeze
      LIST_WINDOW = 30.days
      LIST_PAGE_SIZE = 100
      LIST_MAX_PAGES = 50

      class << self
        def http_client = (@http_client ||= HttpClient.new)

        attr_writer :http_client
      end

      def manifest = MANIFEST

      def test_connection(account)
        return ConnectionResult.new(ok: false, message: I18n.t("payments.connection.not_connected", provider: manifest.label)) unless Connection.connected?(account)

        call(account, :get, "/v1/orders/#{PROBE_ORDER}", not_found_ok: true)
        ConnectionResult.new(ok: true, message: I18n.t("payments.accounts.test.ok"))
      rescue NetworkError => error
        raise Error, error.message
      rescue Error => error
        ConnectionResult.new(ok: false, message: error.message)
      end

      # ---- Conexão por autorização (OAuth) ----

      def authorization_url(_account, app:, state:, redirect_uri:)
        "#{AUTH}?#{{ 'client_id' => app[:client_id], 'response_type' => 'code', 'platform_id' => 'mp', 'state' => state, 'redirect_uri' => redirect_uri }.to_query}"
      end

      def exchange_authorization_code(account, app:, code:, redirect_uri:)
        token_request(app, { "grant_type" => "authorization_code", "code" => code, "redirect_uri" => redirect_uri, "test_token" => (account.environment == "sandbox") })
      end

      def refresh_authorization(_account, app:, refresh_token:)
        token_request(app, { "grant_type" => "refresh_token", "refresh_token" => refresh_token })
      end

      # ---- Avisos por fornecedor (R284w) ----

      # Corpo `{ action, type, data: { id }, user_id, live_mode }`; a assinatura `x-signature` (`ts=…,v1=…`) é o HMAC-SHA256, com o segredo do webhook da
      # aplicação, de `id:<data.id da consulta>;request-id:<x-request-id>;ts:<ts>;` (página de notificações). Devolve a conta conectada e o aviso.
      def parse_provider_notification(body:, headers:, context: {})
        data = JSON.parse(body.to_s.presence || "{}")
        raise Error, I18n.t("payments.accounts.test.bad_payload") unless data.is_a?(Hash)

        authenticate!(data, headers, context)
        order_id = data.dig("data", "id").to_s
        return [ data["user_id"].to_s, [] ] unless data["type"].to_s == "order" && order_id.present?

        status = data["action"].to_s
        [ data["user_id"].to_s, [ Notification.new(event_id: Payloads.event_id(order_id, status), kind: Payloads.kind_of(status), external_id: order_id,
                                                   current_status: status.first(40), occurred_at: Time.current) ] ]
      rescue JSON::ParserError
        raise Error, I18n.t("payments.accounts.test.bad_payload")
      end

      # Pedidos pagos dos últimos 30 dias (a busca filtra pela criação, numa janela de no máximo 30 dias; boleto e Pix valem no máximo 30 dias), com o mesmo
      # identificador do aviso. A passada para no limite de páginas; o que sobrar entra na seguinte ou pela conferência por pedido.
      def list_paid(account, from:, to:)
        notifications = []
        (1..LIST_MAX_PAGES).each do |page|
          query = { "begin_date" => (to - LIST_WINDOW).utc.iso8601, "end_date" => to.utc.iso8601, "status" => "processed", "page" => page, "page_size" => LIST_PAGE_SIZE }.to_query
          data = call(account, :get, "/v1/orders?#{query}")
          orders = Array(data["data"] || data["results"] || data["elements"])
          notifications.concat(orders.filter_map do |order|
            next unless order["id"].present? && order_kind(order) == account.modality

            Notification.new(event_id: Payloads.event_id(order["id"], "processed"), kind: :paid, external_id: order["id"], amount_cents: Payloads.paid_cents(order),
                             occurred_at: to, custom_id: order["external_reference"].presence, current_status: "processed")
          end)
          break if orders.size < LIST_PAGE_SIZE
        end
        notifications
      end

      # ---- Pix ----

      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        body = Payloads.pix_order(custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, description: options[:description])
        order = call(account, :post, "/v1/orders", body: body, idempotency: custom_id)
        refuse_failed!(order)
        Issued.new(external_id: order["id"].to_s, status: "active", amount_cents: amount_cents, due_on: due_on, copy_paste: Payloads.method_data(order)["qr_code"].presence)
      end

      def fetch_pix(account, external_id) = fetched(fetch_order(account, external_id), external_id)

      def cancel_pix(account, external_id) = cancel(account, external_id)

      def refund_pix(account, external_id, amount_cents:, refund_id: nil) = refund(account, external_id, amount_cents, refund_id)

      # ---- Boleto ----

      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        body = Payloads.boleto_order(custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, description: options[:description])
        order = call(account, :post, "/v1/orders", body: body, idempotency: custom_id)
        refuse_failed!(order)
        line = Payloads.method_data(order)["digitable_line"].presence or raise Error, I18n.t("payments.providers.mercadopago.errors.no_digitable_line")
        Issued.new(external_id: order["id"].to_s, status: "active", amount_cents: amount_cents, due_on: line_due_on(line) || due_on, digitable_line: line)
      end

      def fetch_boleto(account, external_id) = fetched(fetch_order(account, external_id), external_id)

      def cancel_boleto(account, external_id) = cancel(account, external_id)

      def change_boleto_due_date(_account, _external_id, _due_on) = raise(NotAvailable, I18n.t("payments.instruments.due_date_unsupported"))

      # A ficha de compensação desenhada aqui (R284e), da linha digitável que o pedido devolve, conferida contra o valor e o vencimento do instrumento.
      def download_boleto_pdf(account, external_id)
        order = fetch_order(account, external_id)
        instrument = PaymentInstrument.find_by(account_id: account.id, external_id: external_id)
        line = Payloads.method_data(order)["digitable_line"].to_s
        due_on = instrument&.due_on || line_due_on(line)
        BoletoSlip.new(**Payloads.slip_attributes(account, order, instrument, due_on)).render
      rescue Febraban::Invalid => error
        raise Error, I18n.t("payments.providers.mercadopago.errors.slip_invalid", detail: error.message)
      end

      # ---- Cartão (campos do Mercado Pago na página, R284ab) ----

      def installments(account, amount_cents:, brand: nil)
        single = [ InstallmentOption.new(installments: 1, installment_cents: amount_cents, total_cents: amount_cents, has_interest: false) ]
        return single if brand.blank? || account.config.fetch("max_installments", 1).to_i <= 1

        query = { "amount" => Payloads.money(amount_cents), "payment_method_id" => brand }.to_query
        Payloads.installment_options(call(account, :get, "/v1/payment_methods/installments?#{query}")).presence || single
      end

      def charge_card(account, custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil, brand: nil)
        raise Error, I18n.t("payments.providers.mercadopago.errors.no_brand") if brand.blank?
        raise Error, I18n.t("payments.instruments.payer_email_missing", provider: manifest.label) if payer[:email].blank?

        body = Payloads.card_order(custom_id: custom_id, amount_cents: amount_cents, installments: installments, token: payment_token, brand: brand, payer: payer, description: description)
        Payloads.card_result(call(account, :post, "/v1/orders", body: body, idempotency: custom_id), fallback_installments: installments)
      end

      def fetch_card(account, external_id) = fetched(fetch_order(account, external_id), external_id)

      def refund_card(account, external_id, amount_cents:) = refund(account, external_id, amount_cents, nil)

      # A Public Key vem da conexão (R284x) e não é segredo; o SDK vem do domínio do Mercado Pago (MPG6).
      def card_checkout_config(account)
        key = account.config["connection_public_key"].presence or raise Error, I18n.t("payments.providers.mercadopago.errors.no_public_key")
        { "public_key" => key, "sdk_url" => SDK_URL }
      end

      def card_checkout_hosts(_account) = CARD_HOSTS

      private
        def fetch_order(account, external_id) = call(account, :get, "/v1/orders/#{escape(external_id)}")

        def fetched(order, external_id)
          Issued.new(external_id: external_id, status: Payloads.status_of(order), amount_cents: Payloads.cents(Payloads.payment(order)["amount"] || order["total_amount"]),
                     copy_paste: Payloads.method_data(order)["qr_code"].presence, digitable_line: Payloads.method_data(order)["digitable_line"].presence,
                     paid_cents: Payloads.paid_cents(order), refunded_cents: Payloads.refunded_cents(order))
        end

        def cancel(account, external_id)
          order = call(account, :post, "/v1/orders/#{escape(external_id)}/cancel", body: {}, idempotency: "cancel-#{external_id}")
          Issued.new(external_id: external_id, status: Payloads.status_of(order).then { |status| status == "active" ? "canceled" : status }, amount_cents: nil)
        end

        def refund(account, external_id, amount_cents, refund_id)
          order = fetch_order(account, external_id)
          payment_id = Payloads.payment(order)["id"].presence or raise Error, I18n.t("payments.providers.mercadopago.errors.nothing_to_refund")
          body = { "transactions" => [ { "id" => payment_id, "amount" => Payloads.money(amount_cents) } ] }
          call(account, :post, "/v1/orders/#{escape(external_id)}/refund", body: body, idempotency: refund_id || "refund-#{external_id}-#{amount_cents}")
          Issued.new(external_id: external_id, status: "paid", amount_cents: amount_cents)
        end

        def refuse_failed!(order)
          raise Error, I18n.t("payments.providers.mercadopago.errors.declined", detail: Payloads.payment(order)["status_detail"] || order["status_detail"]) if order["status"].to_s == "failed"
          raise Error, I18n.t("payments.providers.mercadopago.errors.unexpected") if order["id"].blank?
        end

        def order_kind(order)
          { "pix" => "pix", "boleto" => "boleto", "credit_card" => "card", "debit_card" => "card" }[Payloads.method_data(order)["type"].to_s] ||
            { "pix" => "pix", "boleto" => "boleto" }.fetch(Payloads.method_data(order)["id"].to_s, "card")
        end

        # O vencimento que a linha digitável traz (fator de vencimento), procurado perto de hoje: o Mercado Pago aceita até 30 dias e passa o fim de semana
        # ao dia útil seguinte.
        def line_due_on(line)
          factor = Febraban.parse_digitable(line).due_factor
          (Date.current..(Date.current + 40)).find { |date| Febraban.due_factor(date) == factor }
        rescue Febraban::Invalid
          nil
        end

        def call(account, method, path, body: nil, idempotency: nil, retried: false, not_found_ok: false)
          token = Connection.new.access_token(account)
          headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
          headers["Content-Type"] = "application/json" if body
          headers["X-Idempotency-Key"] = idempotency.to_s.first(128) if idempotency
          response = self.class.http_client.request(method, API + path, headers: headers, body: body&.to_json)
          if response.status == 401 && !retried
            Connection.new.access_token(account.reload, stale: token)
            return call(account, method, path, body: body, idempotency: idempotency, retried: true, not_found_ok: not_found_ok)
          end
          return {} if not_found_ok && response.status == 404

          read(response, idempotent: idempotency.present?)
        end

        # Com o identificador nosso no cabeçalho de idempotência, repetir não duplica (MPG12): falha de rede ou 5xx podem repetir.
        def read(response, idempotent:)
          json = response.body.to_s.strip.empty? ? {} : (JSON.parse(response.body) rescue nil)
          return json || raise(Error, I18n.t("payments.providers.mercadopago.errors.unexpected")) if (200..299).cover?(response.status)

          message = Payloads.error_message(json) || response.status.to_s
          case response.status
          when 401, 403 then raise Error, I18n.t("payments.providers.mercadopago.errors.refused", detail: message)
          when 404 then raise Error, I18n.t("payments.providers.mercadopago.errors.not_found")
          when 409, 423 then raise NetworkError.new(I18n.t("payments.providers.mercadopago.errors.unavailable"), retry_safe: true)
          when 429 then raise NetworkError.new(I18n.t("payments.providers.mercadopago.errors.unavailable"), retry_safe: true)
          when 500..599 then raise NetworkError.new(I18n.t("payments.providers.mercadopago.errors.unavailable"), retry_safe: idempotent)
          else raise Error, I18n.t("payments.providers.mercadopago.errors.rejected", detail: message)
          end
        end

        def token_request(app, body)
          payload = body.merge("client_id" => app[:client_id].to_s, "client_secret" => app[:client_secret].to_s).compact
          response = self.class.http_client.request(:post, "#{API}/oauth/token", headers: { "Content-Type" => "application/json", "Accept" => "application/json" }, body: payload.to_json)
          json = (JSON.parse(response.body) rescue {})
          json = {} unless json.is_a?(Hash)
          raise NetworkError.new(I18n.t("payments.providers.mercadopago.errors.unavailable"), retry_safe: response.status == 429) if response.status == 429 || response.status >= 500
          raise AuthorizationRefused, I18n.t("payments.providers.mercadopago.errors.authorization_refused", detail: Payloads.error_message(json) || response.status) unless response.status == 200 && json["access_token"].present?

          Authorization::Tokens.new(access_token: json["access_token"], refresh_token: json["refresh_token"].presence,
                                    expires_at: (Time.current + json["expires_in"].to_i if json["expires_in"].to_s.match?(/\A\d+\z/)),
                                    account_label: json["user_id"].to_s.presence, account_id: json["user_id"].to_s.presence,
                                    public_values: { "public_key" => json["public_key"].presence }.compact)
        end

        def authenticate!(data, headers, context)
          signature = headers["x-signature"].to_s
          parts = signature.split(",").to_h { |part| part.strip.split("=", 2) }
          environment = data["live_mode"] == false ? "sandbox" : "production"
          secret = Connection.app("mercadopago", environment)&.dig(:webhook_secret)
          raise InvalidSignature, I18n.t("payments.providers.mercadopago.errors.bad_webhook_auth") if secret.blank? || parts["ts"].blank? || parts["v1"].blank?

          data_id = context.dig(:query, "data.id").to_s.presence || data.dig("data", "id").to_s
          data_id = data_id.downcase if data_id.match?(/\A[[:alnum:]]+\z/)
          manifest = { "id" => data_id.presence, "request-id" => headers["x-request-id"].to_s.presence, "ts" => parts["ts"] }.compact.map { |key, value| "#{key}:#{value};" }.join
          expected = OpenSSL::HMAC.hexdigest("SHA256", secret, manifest)
          raise InvalidSignature, I18n.t("payments.providers.mercadopago.errors.bad_webhook_auth") unless parts["v1"].bytesize == expected.bytesize && ActiveSupport::SecurityUtils.fixed_length_secure_compare(parts["v1"], expected)
        end

        def escape(value) = ERB::Util.url_encode(value.to_s)
    end
  end
end
