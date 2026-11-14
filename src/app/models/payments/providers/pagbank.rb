module Payments
  module Providers
    # PagBank (PagSeguro), o terceiro fornecedor real (12, revisão 5; plano do adaptador, decisões PB1 a PB14). Fonte: o portal do PagBank lido em
    # 14/11/2026 (`developer.pagbank.com.br`); o que ele não diz ou contradiz é item do roteiro de homologação (docs/homologacao-pagbank.md).
    #
    # Tudo é um pedido da API Order (`POST /orders`), e o identificador externo do instrumento é o do pedido (`ORDE_...`), que o aviso também traz.
    # Credencial: o CRM é plataforma e usa a conexão por autorização (Connect, PB1; `Payments::Connection`). Boleto com PDF baixado do PagBank e guardado
    # aqui; Pix imediato com validade até o fim do vencimento (PB2) e QR Code gerado aqui (PB13); sem cancelamento nem troca de vencimento pela API
    # (PB3, PB4: cancelar é só aqui). Cartão cifrado no navegador pelo SDK do PagBank, sem chamada de rede: o servidor recebe só o cartão cifrado, que não
    # consegue abrir (R284t), sem 3DS (PB5). Sem idempotência documentada, nada repete depois de tempo esgotado na leitura (PB8). O aviso vem com o pedido
    # inteiro, na URL gravada em cada pedido, autenticado pelo `hmac` da chave da URL (PB7). Sem lista de pagos: a conciliação confere todo ativo a cada
    # dia (PB9). O cliente HTTP é injetável (`Pagbank.http_client=`): nenhum teste chama o PagBank. Tokens e dados do pagador nunca vão a log.
    class Pagbank < Base
      include Boleto
      include Pix
      include Card
      include Authorization

      # SDK de navegador do PagBank (PB6): sem licença declarada e sem versão no endereço, fica fora do repositório público (a exportação o tira) e é
      # conferido pelo SHA-256; `crm:payments:card_sdk[pagbank]` baixa e confere. É um script clássico (cria a global `PagSeguro`), carregado pelo
      # módulo `payments/drivers/pagbank` a partir do nosso domínio, com integridade.
      SDK_FILE = "pagbank-checkout-sdk.js".freeze
      SDK_SOURCE = "https://assets.pagseguro.com.br/checkout-sdk-js/rc/dist/browser/pagseguro.min.js".freeze
      SDK_SHA256 = "19c2123b881f72e540ffb925f926a18c47ac49d79576f3e48fdf2e7c37d77112".freeze

      MANIFEST = Manifest.new(
        provider: "pagbank",
        modalities: %w[boleto pix card],
        fields: [
          # Sem campo de credencial: a conexão é por autorização (R284k). A chave da URL do aviso é gerada na criação e não troca (R284m).
          Manifest::Field.new(name: "webhook_url_key", type: :secret, generated: true),
          Manifest::Field.new(name: "expire_days", type: :number, modalities: %w[boleto pix], min: 1, max: 365, default: 5),
          # O Pix do PagBank não tem multa, juros nem desconto (R284q): os percentuais são só do boleto.
          Manifest::Field.new(name: "fine_percent", type: :number, modalities: %w[boleto], min: 0, max: 10, default: 2),
          Manifest::Field.new(name: "interest_percent", type: :number, modalities: %w[boleto], min: 0, max: 10, default: 1),
          Manifest::Field.new(name: "discount_percent", type: :number, modalities: %w[boleto], min: 0, max: 100, default: 0),
          Manifest::Field.new(name: "write_off_days", type: :number, modalities: %w[boleto], min: 0, max: 120, default: 30),
          Manifest::Field.new(name: "message", type: :text, modalities: %w[boleto], maxlength: 150),
          Manifest::Field.new(name: "max_installments", type: :number, modalities: %w[card], min: 1, max: 12, default: 1),
          Manifest::Field.new(name: "interest_free_installments", type: :number, modalities: %w[card], min: 1, max: 12, default: 1),
          Manifest::Field.new(name: "soft_descriptor", type: :text, modalities: %w[card], maxlength: 22)
        ],
        capabilities: { credentials: "authorization", webhook_auth: %w[hmac], webhook_url: "per_charge", pdf: "file", qr: "text", batch_limit: nil,
                        repeatable_issue: [], cancel: { "boleto" => "local", "pix" => "local" }, due_date_change: false, pix_due: "expires", reconcile_after_days: 1,
                        card_checkout: { driver: "payments/drivers/pagbank", script: nil, token: "encrypted", sdk: SDK_FILE, sdk_sha256: SDK_SHA256 } }
      )

      API_HOSTS = { "production" => "https://api.pagseguro.com", "sandbox" => "https://sandbox.api.pagseguro.com" }.freeze
      CONNECT_HOSTS = { "production" => "https://connect.pagbank.com.br", "sandbox" => "https://connect.sandbox.pagbank.com.br" }.freeze
      SCOPES = "payments.read+payments.create+payments.refund".freeze
      # O PDF do boleto só se baixa do domínio de boletos do PagBank, sem credencial nossa (R273).
      PDF_HOST = /\Aboleto\.(sandbox\.)?pagseguro\.com\.br\z/
      PDF_MAX_BYTES = 5.megabytes
      # Cabeçalho de idempotência candidato: a documentação diz que existe (erro 40005), mas não o nome (lacuna 1). Vai com o nosso identificador; a
      # repetição continua desligada até a homologação confirmar (PB8).
      IDEMPOTENCY_HEADER = "x-idempotency-key".freeze
      # A chave pública do cartão se renova uma vez por ano (o PagBank recomenda menos de 2 anos).
      PUBLIC_KEY_AGE = 365.days
      # Pedido que não existe: a consulta responde 404 com a credencial boa (teste de conexão).
      PROBE_ORDER = "ORDE_00000000-0000-0000-0000-000000000000".freeze

      class << self
        def http_client = (@http_client ||= HttpClient.new)

        attr_writer :http_client
      end

      def manifest = MANIFEST

      # Sem conexão, não há o que testar; conectada, consultar um pedido que não existe prova o token (404), e a recusa diz que não vale (401, 403).
      def test_connection(account)
        return ConnectionResult.new(ok: false, message: I18n.t("payments.connection.not_connected", provider: manifest.label)) unless Connection.connected?(account)

        call(account, :get, "/orders/#{PROBE_ORDER}", not_found_ok: true)
        ConnectionResult.new(ok: true, message: I18n.t("payments.accounts.test.ok"))
      rescue NetworkError => error
        raise Error, error.message
      rescue Error => error
        ConnectionResult.new(ok: false, message: error.message)
      end

      # ---- Conexão por autorização (Connect) ----

      def authorization_url(account, app:, state:, redirect_uri:)
        query = { "response_type" => "code", "client_id" => app[:client_id], "redirect_uri" => redirect_uri, "state" => state }.to_query
        # Os escopos vão unidos por "+", como a página do Connect escreve (o "+" é o espaço da consulta).
        "#{CONNECT_HOSTS.fetch(account.environment)}/oauth2/authorize?#{query}&scope=#{SCOPES}"
      end

      def exchange_authorization_code(account, app:, code:, redirect_uri:)
        token_request(account, app, { "grant_type" => "authorization_code", "code" => code, "redirect_uri" => redirect_uri })
      end

      def refresh_authorization(account, app:, refresh_token:)
        token_request(account, app, { "grant_type" => "refresh_token", "refresh_token" => refresh_token })
      end

      # ---- Avisos (R281, R284b, R284s) ----

      # O pedido inteiro, em JSON, autenticado pelo `hmac` da chave da URL (PB7). O formato antigo (`notificationCode`, de devolução, chargeback e saldo)
      # só se lê com e-mail e token no endereço da API antiga: vai a "para conferir" sem consulta (PB12). Corpo sem nada reconhecível: lista vazia.
      def parse_notification(account, body:, headers:, context: {})
        text = body.to_s.strip
        if text.start_with?("{")
          order = JSON.parse(text)
          return [] unless order.is_a?(Hash) && order["id"].to_s.start_with?("ORDE_")

          authenticate!(account, context)
          [ Payloads.notification(order) ]
        elsif (code = Rack::Utils.parse_query(text)["notificationCode"].to_s).match?(/\A[A-Za-z0-9\-]{6,80}\z/)
          authenticate!(account, context)
          [ Notification.new(event_id: "legacy:#{code}", kind: :unreadable, token: code, current_status: Rack::Utils.parse_query(text)["notificationType"].to_s.first(40).presence) ]
        else
          []
        end
      rescue JSON::ParserError
        raise Error, I18n.t("payments.accounts.test.bad_payload")
      end

      # O PagBank não cadastra webhook: o endereço vai em cada pedido (R284m).
      def register_webhook(_account) = raise(NotAvailable, I18n.t("payments.webhook_registration.per_charge"))

      # ---- Pix (imediato com validade, R284q) ----

      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        body = Payloads.pix_order(custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, notification_url: options[:notification_url],
                                  description: options[:description])
        order = call(account, :post, "/orders", body: body, idempotency: custom_id)
        refuse_declined!(order)
        Issued.new(external_id: order["id"].to_s, status: "active", amount_cents: amount_cents, due_on: due_on, copy_paste: Payloads.copy_paste(order))
      end

      def fetch_pix(account, external_id)
        order = fetch_order(account, external_id)
        current = Payloads.charge(order)
        Issued.new(external_id: external_id, status: Payloads.status_of(order, "pix"), amount_cents: Array(order["qr_codes"]).first&.dig("amount", "value") || current.dig("amount", "value"),
                   copy_paste: Payloads.copy_paste(order), paid_cents: Payloads.paid_cents(current), refunded_cents: Payloads.refunded_cents(current))
      end

      # Sem cancelamento documentado (PB3): o `Issuer` cancela só aqui (`cancel: "local"`), e esta chamada não existe.
      def cancel_pix(_account, _external_id) = raise(NotAvailable, I18n.t("payments.providers.pagbank.errors.no_cancel"))

      def refund_pix(account, external_id, amount_cents:, refund_id: nil) = refund(account, external_id, amount_cents)

      # ---- Boleto ----

      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        raise Error, I18n.t("payments.providers.pagbank.errors.boleto_minimum") if amount_cents.to_i < Payloads::BOLETO_MIN_CENTS

        body = Payloads.boleto_order(custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, options: options, notification_url: options[:notification_url])
        order = call(account, :post, "/orders", body: body, idempotency: custom_id)
        refuse_declined!(order)
        Issued.new(external_id: order["id"].to_s, status: "active", amount_cents: amount_cents, due_on: Payloads.boleto_due(order) || due_on, digitable_line: Payloads.boleto_line(order))
      end

      def fetch_boleto(account, external_id)
        order = fetch_order(account, external_id)
        current = Payloads.charge(order)
        Issued.new(external_id: external_id, status: Payloads.status_of(order, "boleto"), amount_cents: current.dig("amount", "value"), due_on: Payloads.boleto_due(order),
                   digitable_line: Payloads.boleto_line(order), paid_cents: Payloads.paid_cents(current), refunded_cents: Payloads.refunded_cents(current))
      end

      def cancel_boleto(_account, _external_id) = raise(NotAvailable, I18n.t("payments.providers.pagbank.errors.no_cancel"))

      def change_boleto_due_date(_account, _external_id, _due_on) = raise(NotAvailable, I18n.t("payments.instruments.due_date_unsupported"))

      # O PDF vem de um link do PagBank na resposta do pedido: baixado daqui, só do domínio de boletos, sem credencial nossa, e conferido (R273).
      def download_boleto_pdf(account, external_id)
        url = Payloads.pdf_link(fetch_order(account, external_id)) or raise Error, I18n.t("payments.providers.pagbank.errors.pdf_missing")
        uri = URI.parse(url)
        raise Error, I18n.t("payments.providers.pagbank.errors.pdf_host") unless uri.is_a?(URI::HTTPS) && uri.host.to_s.downcase.match?(PDF_HOST)

        response = self.class.http_client.request(:get, url, max_bytes: PDF_MAX_BYTES, read_timeout: 30)
        raise Error, I18n.t("payments.providers.pagbank.errors.pdf_download", status: response.status) unless response.status == 200
        raise Error, I18n.t("payments.providers.pagbank.errors.pdf_invalid") unless response.body.to_s.b.start_with?("%PDF")

        response.body.b
      rescue URI::InvalidURIError
        raise Error, I18n.t("payments.providers.pagbank.errors.pdf_host")
      end

      # ---- Cartão (cartão cifrado no navegador, R284t) ----

      # Parcelas pela API de taxas, por bandeira (o navegador descobre a bandeira sem enviar o número). As sem juros são as que o credor assume.
      def installments(account, amount_cents:, brand: nil)
        single = [ InstallmentOption.new(installments: 1, installment_cents: amount_cents, total_cents: amount_cents, has_interest: false) ]
        maximum = account.config.fetch("max_installments", 1).to_i
        return single if brand.blank? || maximum <= 1

        plans = fees(account, amount_cents, maximum, brand)
        plans.presence || single
      end

      # `payment_token` aqui é o cartão cifrado pelo SDK (`encrypted`). Acima das parcelas sem juros, o total com juros vem da API de taxas pela bandeira;
      # o pagamento entra pelo valor do instrumento (R284v). Sem repetição: o cartão cifrado vale uma vez.
      def charge_card(account, custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil, brand: nil)
        interest = 0
        if installments.to_i > account.config.fetch("interest_free_installments", 1).to_i
          plan = brand.present? && fees(account, amount_cents, installments, brand).find { |option| option.installments == installments.to_i }
          raise Error, I18n.t("payments.providers.pagbank.errors.installments_unavailable") unless plan

          interest = [ plan.total_cents - amount_cents.to_i, 0 ].max
        end
        body = Payloads.card_order(custom_id: custom_id, amount_cents: amount_cents, installments: installments, encrypted: payment_token, payer: payer, description: description,
                                   notification_url: notification_url, interest_cents: interest, soft_descriptor: soft_descriptor(account))
        Payloads.card_result(call(account, :post, "/orders", body: body, idempotency: custom_id), fallback_installments: installments)
      end

      def fetch_card(account, external_id)
        order = fetch_order(account, external_id)
        current = Payloads.charge(order)
        status = case current["status"].to_s
        when "PAID" then "paid"
        when "CANCELED" then Payloads.refunded_cents(current).positive? ? "paid" : "canceled"
        when "DECLINED" then "failed"
        else "active"
        end
        Issued.new(external_id: external_id, status: status, amount_cents: current.dig("amount", "value").to_i - Payloads.buyer_interest(current),
                   paid_cents: Payloads.paid_cents(current), refunded_cents: Payloads.refunded_cents(current))
      end

      def refund_card(account, external_id, amount_cents:) = refund(account, external_id, amount_cents)

      # Valores públicos para o navegador: a chave pública da conta (não é segredo), o endereço do SDK no nosso domínio e a integridade dele.
      def card_checkout_config(account)
        { "public_key" => public_key(account), "sdk_url" => ActionController::Base.helpers.asset_path(SDK_FILE),
          "sdk_integrity" => "sha256-#{[ [ SDK_SHA256 ].pack('H*') ].pack('m0')}" }
      end

      # O `encryptCard` não chama rede nenhuma (lido no SDK): sem 3DS (PB5), a página não libera domínio externo.
      def card_checkout_hosts(_account) = { script: [], connect: [], frame: [], img: [] }

      private
        def fetch_order(account, external_id) = call(account, :get, "/orders/#{escape(external_id)}")

        def refund(account, external_id, amount_cents)
          charge_id = Payloads.charge(fetch_order(account, external_id))["id"].presence or raise Error, I18n.t("payments.providers.pagbank.errors.nothing_to_refund")
          call(account, :post, "/charges/#{escape(charge_id)}/cancel", body: { "amount" => { "value" => amount_cents.to_i } })
          Issued.new(external_id: external_id, status: "paid", amount_cents: amount_cents)
        end

        def refuse_declined!(order)
          raise Error, I18n.t("payments.providers.pagbank.errors.declined") if Payloads.charge(order)["status"].to_s == "DECLINED"
          raise Error, I18n.t("payments.providers.pagbank.errors.unexpected") if order["id"].blank?
        end

        def fees(account, amount_cents, maximum, brand)
          free = [ account.config.fetch("interest_free_installments", 1).to_i, maximum.to_i ].min
          query = { "payment_methods" => "CREDIT_CARD", "value" => amount_cents.to_i, "max_installments" => maximum.to_i, "max_installments_no_interest" => free }.to_query
          Payloads.installment_plans(call(account, :get, "/charges/fees/calculate?#{query}"), brand).select { |option| option.installments <= maximum.to_i }
        end

        def soft_descriptor(account) = I18n.transliterate(account.config["soft_descriptor"].to_s).gsub(/[^A-Za-z0-9 ]/, "").strip.first(22).presence

        # A chave pública do cartão da conta, guardada na integração (não é segredo) e renovada uma vez por ano.
        def public_key(account, now: Time.current)
          stored = account.config["card_public_key"].presence
          fetched_at = account.config["card_public_key_at"].presence
          return stored if stored && fetched_at && Time.iso8601(fetched_at) > now - PUBLIC_KEY_AGE

          key = call(account, :post, "/public-keys", body: { "type" => "card" })["public_key"].presence or raise Error, I18n.t("payments.providers.pagbank.errors.no_public_key")
          account.update_columns(config: account.config.merge("card_public_key" => key, "card_public_key_at" => now.iso8601))
          key
        end

        # Chamada à API com o token da conexão. 401 uma vez renova o token (só se ainda for o que falhou) e tenta de novo.
        def call(account, method, path, body: nil, idempotency: nil, retried: false, not_found_ok: false)
          token = Connection.new.access_token(account)
          headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
          headers["Content-Type"] = "application/json" if body
          headers[IDEMPOTENCY_HEADER] = idempotency.to_s if idempotency
          response = self.class.http_client.request(method, API_HOSTS.fetch(account.environment) + path, headers: headers, body: body&.to_json)
          if response.status == 401 && !retried
            Connection.new.access_token(account.reload, stale: token)
            return call(account, method, path, body: body, idempotency: idempotency, retried: true, not_found_ok: not_found_ok)
          end
          return {} if not_found_ok && response.status == 404

          read(response)
        end

        def read(response)
          json = response.body.to_s.strip.empty? ? {} : (JSON.parse(response.body) rescue nil)
          return json || raise(Error, I18n.t("payments.providers.pagbank.errors.unexpected")) if (200..299).cover?(response.status)

          message = Payloads.error_message(json) || response.status.to_s
          # `40004 rate_limit` vem com HTTP 400 e é indisponibilidade, não recusa: o pedido não foi processado (plano, seção "Padrão de adaptadores").
          raise NetworkError.new(I18n.t("payments.providers.pagbank.errors.unavailable"), retry_safe: true) if response.status == 429 || Payloads.error_codes(json).include?("40004")

          case response.status
          when 401, 403 then raise Error, I18n.t("payments.providers.pagbank.errors.refused", detail: message)
          when 404 then raise Error, I18n.t("payments.providers.pagbank.errors.not_found")
          when 500..599 then raise NetworkError.new(I18n.t("payments.providers.pagbank.errors.unavailable"), retry_safe: false)
          else raise Error, I18n.t("payments.providers.pagbank.errors.rejected", detail: message)
          end
        end

        # Troca de código ou renovação no Connect: `X_CLIENT_ID`, `X_CLIENT_SECRET` e o token da conta da plataforma (página do Connect; qual token vai no
        # `Authorization` é a lacuna 9). Recusa vira `AuthorizationRefused`; indisponibilidade, erro de rede.
        def token_request(account, app, body)
          headers = { "X_CLIENT_ID" => app[:client_id].to_s, "X_CLIENT_SECRET" => app[:client_secret].to_s, "Content-Type" => "application/json", "Accept" => "application/json" }
          headers["Authorization"] = "Bearer #{app[:platform_token]}" if app[:platform_token].present?
          response = self.class.http_client.request(:post, "#{API_HOSTS.fetch(account.environment)}/oauth2/token", headers: headers, body: body.to_json)
          json = (JSON.parse(response.body) rescue {})
          json = {} unless json.is_a?(Hash)
          if response.status == 429 || response.status >= 500
            raise NetworkError.new(I18n.t("payments.providers.pagbank.errors.unavailable"), retry_safe: response.status == 429)
          end
          raise AuthorizationRefused, I18n.t("payments.providers.pagbank.errors.authorization_refused", detail: Payloads.error_message(json) || response.status) unless response.status == 200 && json["access_token"].present?

          Authorization::Tokens.new(access_token: json["access_token"], refresh_token: json["refresh_token"].presence, expires_at: expires_at(json),
                                    account_label: json["account_id"].presence)
        end

        # A resposta traz "a data de expiração" (página do Connect): em segundos (`expires_in`) ou em data; sem nenhuma, o token vale até o primeiro 401.
        def expires_at(json)
          if json["expires_in"].to_s.match?(/\A\d+\z/) then Time.current + json["expires_in"].to_i
          elsif json["expires_at"].present? then Time.iso8601(json["expires_at"].to_s)
          end
        rescue ArgumentError
          nil
        end

        def authenticate!(account, context)
          raise InvalidSignature, I18n.t("payments.providers.pagbank.errors.bad_webhook_auth") unless WebhookUrl.valid?(account, context.dig(:query, "hmac"))
        end

        def escape(value) = ERB::Util.url_encode(value.to_s)
    end
  end
end
