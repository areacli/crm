module Payments
  module Providers
    # Efí (ex-Gerencianet), o primeiro fornecedor real (IP-5). Parte B: boleto (API de cobranças, `POST /v1/charge/one-step` com `banking_billet`)
    # e Pix com vencimento (API Pix, `PUT /v2/cobv/:txid`, com certificado mTLS), mais o teste de conexão. Parte C: cartão por checkout
    # transparente (a biblioteca `payment-token-efi` roda no navegador; aqui só chega o `payment_token`), parcelas, reembolso de cartão e devolução
    # de Pix. Parte D: leitura dos avisos (Pix por `pix[]`, cobranças por token que se consulta em `GET /v1/notification/:token`) e a consulta de pago e devolvido. O cliente HTTP é injetável (`Efi.http_client=`): nenhum teste chama a Efí, e o roteiro de homologação está em docs/homologacao-efi.md.
    # Segredos (Client ID/Secret, certificado) são lidos da conta só durante a chamada e nunca vão a log, mensagem de erro ou resposta.
    class Efi < Base
      include Boleto
      include Pix
      include Card

      MANIFEST = Manifest.new(
        provider: "efi",
        modalities: %w[boleto pix card],
        fields: [
          Manifest::Field.new(name: "client_id", type: :secret, required: true),
          Manifest::Field.new(name: "client_secret", type: :secret, required: true),
          Manifest::Field.new(name: "payee_code", type: :text, modalities: %w[card], required: true, maxlength: 64),
          Manifest::Field.new(name: "certificate", type: :file, modalities: %w[pix], required: true, format: :pkcs12, password_field: "certificate_password"),
          Manifest::Field.new(name: "certificate_password", type: :secret, modalities: %w[pix]),
          Manifest::Field.new(name: "pix_key", type: :text, modalities: %w[pix], required: true, maxlength: 77),
          Manifest::Field.new(name: "webhook_secret", type: :secret, generated: true),
          # Padrões por modalidade (IP, "Modalidades habilitadas"): valem na emissão quando o pedido não diz outra coisa.
          Manifest::Field.new(name: "expire_days", type: :number, modalities: %w[boleto pix], min: 1, max: 365, default: 5),
          Manifest::Field.new(name: "fine_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 10, default: 2),
          Manifest::Field.new(name: "interest_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 10, default: 1),
          Manifest::Field.new(name: "discount_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 100, default: 0),
          Manifest::Field.new(name: "write_off_days", type: :number, modalities: %w[boleto], min: 0, max: 120, default: 30),
          Manifest::Field.new(name: "message", type: :text, modalities: %w[boleto], maxlength: 400),
          Manifest::Field.new(name: "max_installments", type: :number, modalities: %w[card], min: 1, max: 12, default: 1)
        ],
        # Cartão: a biblioteca de tokenização (`payment-token-efi` 3.4.1, MIT, versão ESM) está fixada em vendor/javascript e o SHA-256 daqui é conferido por teste;
        # `driver` é o módulo do navegador que a usa. Os domínios que ela acessa vêm de `card_checkout_hosts` (conferidos no código da biblioteca; a
        # homologação confirma no console do navegador). O webhook do Pix usa mTLS ou IP e HMAC na URL (IP-P4).
        capabilities: { webhook_auth: %w[hmac mtls ip], pdf: "file", qr: "image", batch_limit: nil,
                        card_checkout: { driver: "payments/drivers/efi", script: "payment-token-efi", script_version: "3.4.1",
                                         script_sha256: "9aa92bf4c90e9a35c476edc0c306dec56a5dfebf0f84652e86149abdbfe312e1" } }
      )

      HOSTS = {
        billing: { "production" => "https://cobrancas.api.efipay.com.br", "sandbox" => "https://cobrancas-h.api.efipay.com.br" },
        pix: { "production" => "https://pix.api.efipay.com.br", "sandbox" => "https://pix-h.api.efipay.com.br" }
      }.freeze
      # O PDF do boleto só é baixado de endereços da própria Efí (o endereço vem na resposta dela; nunca se segue um endereço de outro domínio).
      PDF_HOST_SUFFIXES = %w[.efipay.com.br .gerencianet.com.br].freeze
      PDF_MAX_BYTES = 5.megabytes
      CARD_BRANDS = %w[visa mastercard amex elo hipercard].freeze
      # Domínios da biblioteca de tokenização no navegador (lidos no código dela, versão 3.4.1): o tokenizador, a API de cobranças do ambiente (chave pública),
      # a API de cobranças de produção (impressão digital 3DS, também em homologação) e o script de impressão digital antifraude (ClearSale), que a
      # biblioteca carrega por conta própria e cuja ausência não impede o token.
      FINGERPRINT_SCRIPT_HOSTS = %w[https://device.clearsale.com.br].freeze
      FINGERPRINT_CONNECT_HOSTS = %w[https://device.clearsale.com.br https://web.fpcs-monitor.com.br].freeze

      class << self
        def http_client = (@http_client ||= HttpClient.new)

        attr_writer :http_client
      end

      def manifest = MANIFEST

      # Autentica na API que a modalidade usa (cobranças para boleto e cartão; Pix, com o certificado) e diz se as credenciais valem.
      def test_connection(account)
        api = account.modality == "pix" ? :pix : :billing
        token_for(account, api)
        ConnectionResult.new(ok: true, message: I18n.t("payments.accounts.test.ok"))
      rescue NetworkError => error
        raise Error, error.message
      rescue Error => error
        ConnectionResult.new(ok: false, message: error.message)
      end

      # ---- Avisos (parte D, R281) ----

      # Lê o aviso e confere quem o mandou, sem chamar a Efí. Pix (`pix[]`): mTLS verificado pelo proxy, ou o `hmac` da URL mais o IP da Efí (IP-P4);
      # cobranças (só um token no corpo): o `hmac` da URL, e a verdade vem da consulta do token no job. Corpo sem nada reconhecível (o teste que a
      # Efí manda ao registrar o webhook) devolve lista vazia.
      def parse_notification(account, body:, headers:, context: {})
        data = parse_body(body)
        if data["pix"].is_a?(Array)
          authenticate_pix!(account, context)
          data["pix"].flat_map { |pix| pix_notifications(pix) }
        elsif data["notification"].to_s.match?(/\A[A-Za-z0-9\-_.]{8,200}\z/)
          raise InvalidSignature, I18n.t("payments.providers.efi.errors.bad_webhook_auth") unless WebhookUrl.valid?(account, context.dig(:query, "hmac"))

          [ Notification.new(event_id: data["notification"], kind: :check, token: data["notification"], reprocess: true) ]
        else
          []
        end
      end

      # Registra na Efí o endereço do nosso webhook para a chave Pix da conta (`PUT /v2/webhook/:chave`). Com `skip_mtls`, manda `x-skip-mtls-checking: true`
      # (a Efí não exige o certificado de cliente do nosso servidor; a autenticação passa a ser o HMAC da URL e o IP, IP-P4). O `?ignorar=` no fim impede a
      # Efí de acrescentar `/pix` ao caminho (a rota aceita os dois, de qualquer modo). Chamado pela tarefa `crm:payments:register_pix_webhook`, nunca por tela.
      def register_pix_webhook(account, skip_mtls: true)
        url = WebhookUrl.for(account) or raise Error, I18n.t("payments.providers.efi.errors.no_webhook_url")
        key = account.config["pix_key"].presence or raise Error, I18n.t("payments.providers.efi.errors.no_pix_key")
        call(account, :pix, :put, "/v2/webhook/#{escape(key)}", body: { "webhookUrl" => "#{url}&ignorar=" }, extra_headers: { "x-skip-mtls-checking" => skip_mtls.to_s })
        true
      end

      # O aviso de cobranças só traz um token: a lista de mudanças vem de `GET /v1/notification/:token` (a Efí só dá o aviso por entregue depois disso).
      def expand_notification(account, notification)
        return [ notification ] unless notification.kind == :check && notification.token

        Array(call(account, :billing, :get, "/v1/notification/#{escape(notification.token)}")["data"]).filter_map do |entry|
          charge_id = entry.dig("identifiers", "charge_id")
          next if charge_id.blank?

          current = entry.dig("status", "current").to_s
          kind = { "paid" => :paid, "settled" => :paid, "refunded" => :refunded, "canceled" => :canceled, "unpaid" => :expired }.fetch(current, :other)
          Notification.new(event_id: "#{notification.token}:#{entry['id']}", kind: kind, external_id: charge_id, amount_cents: (entry["value"] if entry["value"].is_a?(Integer)),
                           occurred_at: time_of(entry["received_by_bank_at"].presence || entry["created_at"]), custom_id: entry["custom_id"].presence,
                           previous_status: entry.dig("status", "previous"), current_status: current)
        end
      end

      # ---- Boleto ----

      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        body = Payloads.billet_body(custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, options: options)
        billet_issued(call(account, :billing, :post, "/v1/charge/one-step", body: body).fetch("data"), fallback_amount: amount_cents, fallback_due: due_on)
      end

      def fetch_boleto(account, external_id)
        billet_issued(call(account, :billing, :get, "/v1/charge/#{escape(external_id)}").fetch("data"))
      end

      def cancel_boleto(account, external_id)
        call(account, :billing, :put, "/v1/charge/#{escape(external_id)}/cancel")
        Issued.new(external_id: external_id, status: "canceled", amount_cents: nil)
      end

      def change_boleto_due_date(account, external_id, due_on)
        call(account, :billing, :put, "/v1/charge/#{escape(external_id)}/billet", body: { "expire_at" => due_on.iso8601 })
        Issued.new(external_id: external_id, status: "active", amount_cents: nil, due_on: due_on)
      end

      # Consulta a cobrança para achar o endereço do PDF e o baixa daqui, sem credencial nossa na requisição (R273).
      def download_boleto_pdf(account, external_id)
        data = call(account, :billing, :get, "/v1/charge/#{escape(external_id)}").fetch("data")
        url = find_pdf_url(data) or raise Error, I18n.t("payments.providers.efi.errors.pdf_missing")
        host = URI.parse(url).host.to_s.downcase
        raise Error, I18n.t("payments.providers.efi.errors.pdf_host") unless URI.parse(url).is_a?(URI::HTTPS) && PDF_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

        response = self.class.http_client.request(:get, url, max_bytes: PDF_MAX_BYTES, read_timeout: 30)
        raise Error, I18n.t("payments.providers.efi.errors.pdf_download", status: response.status) unless response.status == 200
        raise Error, I18n.t("payments.providers.efi.errors.pdf_invalid") unless response.body.to_s.b.start_with?("%PDF")

        response.body.b
      rescue URI::InvalidURIError
        raise Error, I18n.t("payments.providers.efi.errors.pdf_host")
      end

      # ---- Pix (cobrança com vencimento) ----

      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        key = account.config["pix_key"].presence or raise Error, I18n.t("payments.providers.efi.errors.no_pix_key")
        body = Payloads.pix_body(amount_cents: amount_cents, due_on: due_on, payer: payer, pix_key: key, options: options)
        data = idempotent { call(account, :pix, :put, "/v2/cobv/#{escape(custom_id)}", body: body) }
        issued = pix_issued(data, custom_id)
        issued.with(qr_png: qr_png_of(account, data.dig("loc", "id")))
      end

      def fetch_pix(account, external_id)
        pix_issued(idempotent { call(account, :pix, :get, "/v2/cobv/#{escape(external_id)}") }, external_id)
      end

      def cancel_pix(account, external_id)
        data = idempotent { call(account, :pix, :patch, "/v2/cobv/#{escape(external_id)}", body: { "status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR" }) }
        pix_issued(data, external_id)
      end

      def refund_pix(account, external_id, amount_cents:, refund_id: nil)
        paid = idempotent { call(account, :pix, :get, "/v2/cobv/#{escape(external_id)}") }
        end_to_end_id = Array(paid["pix"]).first&.dig("endToEndId").presence or raise Error, I18n.t("payments.providers.efi.errors.pix_not_paid")
        refund_id ||= Digest::SHA256.hexdigest("#{external_id}:#{amount_cents}")[0, 32]
        idempotent { call(account, :pix, :put, "/v2/pix/#{escape(end_to_end_id)}/devolucao/#{escape(refund_id)}", body: { "valor" => Payloads.decimal(amount_cents) }) }
        Issued.new(external_id: external_id, status: "paid", amount_cents: amount_cents)
      end

      # ---- Cartão (checkout transparente) ----

      # Parcelas pela API de cobranças (por bandeira, que o navegador descobre sem enviar o número). Sem bandeira, só à vista.
      def installments(account, amount_cents:, brand: nil)
        brand = brand.to_s.downcase
        return [ InstallmentOption.new(installments: 1, installment_cents: amount_cents, total_cents: amount_cents, has_interest: false) ] unless CARD_BRANDS.include?(brand)

        data = call(account, :billing, :get, "/v1/installments?brand=#{brand}&total=#{amount_cents.to_i}").fetch("data")
        Array(data["installments"]).filter_map do |option|
          count = option["installment"].to_i
          next unless count.positive?

          interest = option["has_interest"] == true
          InstallmentOption.new(installments: count, installment_cents: option["value"].to_i, total_cents: interest ? option["value"].to_i * count : amount_cents, has_interest: interest)
        end
      end

      # Cobrança em um passo com o `payment_token` (R278): o servidor nunca vê dado de cartão. `approved` é aprovado pelo emissor, a confirmar pelo aviso;
      # `unpaid` é recusa, com `refusal.reason` e `refusal.retry`. Sem repetição automática aqui: quem chama decide (o cartão pode ter sido cobrado).
      def charge_card(account, custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil)
        body = Payloads.card_body(custom_id: custom_id, amount_cents: amount_cents, installments: installments, payment_token: payment_token, payer: payer, description: description,
                                  notification_url: notification_url)
        data = call(account, :billing, :post, "/v1/charge/one-step", body: body).fetch("data")
        Payloads.card_result(data, fallback_installments: installments)
      end

      def fetch_card(account, external_id)
        data = call(account, :billing, :get, "/v1/charge/#{escape(external_id)}").fetch("data")
        # Cartão reembolsado continua pago (o estorno é outro fato); o valor devolvido é o total (a Efí não mostra reembolso parcial nesta consulta).
        return Issued.new(external_id: external_id, status: "paid", amount_cents: data["total"], paid_cents: data["total"], refunded_cents: data["total"]) if data["status"].to_s == "refunded"

        status = Payloads::BILLET_STATUS.fetch(data["status"].to_s, "active")
        Issued.new(external_id: external_id, status: status, amount_cents: data["total"], paid_cents: (data["total"] if status == "paid"))
      end

      # Reembolso total (sem valor) ou parcial, em centavos; o fornecedor processa depois e avisa (parte D).
      def refund_card(account, external_id, amount_cents:)
        call(account, :billing, :post, "/v1/charge/card/#{escape(external_id)}/refund", body: { "amount" => amount_cents.to_i })
        Issued.new(external_id: external_id, status: "paid", amount_cents: amount_cents)
      end

      def card_checkout_config(account) = { "payee_code" => account.config["payee_code"].to_s, "environment" => account.environment == "production" ? "production" : "sandbox" }

      # Domínios que a página libera para o script e a conexão (e só eles).
      def card_checkout_hosts(account)
        api = account.environment == "production" ? [ HOSTS[:billing]["production"] ] : [ HOSTS[:billing]["sandbox"], HOSTS[:billing]["production"] ]
        { script: FINGERPRINT_SCRIPT_HOSTS, connect: [ "https://tokenizer.sejaefi.com.br", *api, *FINGERPRINT_CONNECT_HOSTS ], frame: [], img: [] }
      end

      private
        # Chamada à Efí: token, requisição e leitura da resposta. Token recusado uma vez (expirou antes da hora) é pedido de novo.
        def call(account, api, method, path, body: nil, retried: false, extra_headers: {})
          token = token_for(account, api)
          headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }.merge(extra_headers)
          headers["Content-Type"] = "application/json" if body
          response = self.class.http_client.request(method, host(account, api) + path, headers: headers, body: body&.to_json, tls: (tls_for(account) if api == :pix))
          if response.status == 401 && !retried
            TokenStore.forget(token_key(account, api))
            return call(account, api, method, path, body: body, retried: true, extra_headers: extra_headers)
          end
          read(response)
        end

        def read(response)
          json = response.body.to_s.strip.empty? ? {} : (JSON.parse(response.body) rescue nil)
          return json || raise(Error, I18n.t("payments.providers.efi.errors.unexpected")) if (200..299).cover?(response.status)

          message = Payloads.error_message(json)
          case response.status
          when 401, 403 then raise Error, I18n.t("payments.providers.efi.errors.refused", detail: message)
          when 429, 503 then raise NetworkError.new(I18n.t("payments.providers.efi.errors.unavailable"), retry_safe: true)
          when 500..599 then raise NetworkError.new(I18n.t("payments.providers.efi.errors.unavailable"), retry_safe: false)
          else raise Error, message
          end
        end

        # O Pix pelo `txid` nosso é idempotente: qualquer falha de rede pode ser repetida sem duplicar.
        def idempotent
          yield
        rescue NetworkError => error
          raise NetworkError.new(error.message, retry_safe: true)
        end

        def token_for(account, api)
          TokenStore.fetch(token_key(account, api)) do
            client_id = account.secrets["client_id"].presence
            client_secret = account.secrets["client_secret"].presence
            raise Error, I18n.t("payments.providers.efi.errors.no_credentials") unless client_id && client_secret

            path, body = api == :pix ? [ "/oauth/token", { "grant_type" => "client_credentials" } ] : [ "/v1/authorize", { "grant_type" => "client_credentials" } ]
            response = self.class.http_client.request(:post, host(account, api) + path, body: body.to_json, tls: (tls_for(account) if api == :pix),
                                                       headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}", "Content-Type" => "application/json" })
            json = (JSON.parse(response.body) rescue {})
            token = json["access_token"] if response.status == 200
            raise Error, I18n.t("payments.providers.efi.errors.credential_refused") if [ 400, 401, 403 ].include?(response.status) || (response.status == 200 && token.blank?)
            raise NetworkError.new(I18n.t("payments.providers.efi.errors.unavailable"), retry_safe: true) unless response.status == 200

            [ token, json["expires_in"].presence || 600 ]
          end
        end

        def token_key(account, api)
          Digest::SHA256.hexdigest([ api, account.environment, account.secrets["client_id"], account.secrets["client_secret"], account.secrets["certificate"].to_s.hash ].join("|"))
        end

        def host(account, api) = HOSTS.fetch(api).fetch(account.environment)

        # Certificado e chave do .p12 da conta, abertos agora e só na memória desta chamada.
        def tls_for(account)
          encoded = account.secrets["certificate"].presence or raise Error, I18n.t("payments.providers.efi.errors.no_certificate")
          pkcs12 = OpenSSL::PKCS12.new(Base64.strict_decode64(encoded), account.secrets["certificate_password"].to_s)
          { cert: pkcs12.certificate, key: pkcs12.key }
        rescue OpenSSL::PKCS12::PKCS12Error, ArgumentError
          raise Error, I18n.t("payments.providers.efi.errors.certificate_unreadable")
        end

        def parse_body(body)
          text = body.to_s.strip
          return {} if text.empty?

          parsed = text.start_with?("{") ? JSON.parse(text) : Rack::Utils.parse_nested_query(text)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          raise Error, I18n.t("payments.accounts.test.bad_payload")
        end

        def authenticate_pix!(account, context)
          return if Rails.configuration.x.payments.trust_mtls_header && context[:client_verified]

          ips = Rails.configuration.x.payments.webhook_ips
          origin_ok = ips.empty? || ips.include?(context[:remote_ip].to_s)
          raise InvalidSignature, I18n.t("payments.providers.efi.errors.bad_webhook_auth") unless origin_ok && WebhookUrl.valid?(account, context.dig(:query, "hmac"))
        end

        # Um Pix recebido (`endToEndId` é a chave) e as devoluções dele (uma por `id` e estado, porque o mesmo `id` passa de EM_PROCESSAMENTO a DEVOLVIDO).
        def pix_notifications(pix)
          return [] unless pix.is_a?(Hash) && pix["endToEndId"].present?

          e2e = pix["endToEndId"].to_s
          received = Notification.new(event_id: e2e, kind: :paid, external_id: pix["txid"].presence, amount_cents: cents_of(pix["valor"]).nonzero?, occurred_at: time_of(pix["horario"]), end_to_end_id: e2e)
          refunds = Array(pix["devolucoes"]).filter_map do |refund|
            next unless refund.is_a?(Hash) && refund["id"].present?

            Notification.new(event_id: "#{e2e}:#{refund['id']}:#{refund['status']}", kind: (refund["status"].to_s == "DEVOLVIDO" ? :refunded : :other), external_id: pix["txid"].presence,
                             amount_cents: cents_of(refund["valor"]).nonzero?, occurred_at: time_of(refund.dig("horario", "liquidacao") || refund.dig("horario", "solicitacao")),
                             end_to_end_id: e2e, current_status: refund["status"].to_s.first(40))
          end
          [ received, *refunds ]
        end

        def time_of(value)
          Time.zone.parse(value.to_s).presence if value.present?
        rescue ArgumentError
          nil
        end

        def escape(segment) = ERB::Util.url_encode(segment.to_s)

        def billet_issued(data, fallback_amount: nil, fallback_due: nil)
          billet = nested_billet(data) || data
          due = billet["expire_at"] || data["expire_at"]
          status = Payloads::BILLET_STATUS.fetch(data["status"].to_s, "active")
          Issued.new(external_id: (data["charge_id"] || data["id"]).to_s, status: status, paid_cents: (data["total"] if status == "paid"),
                     amount_cents: data["total"] || fallback_amount, due_on: (Date.iso8601(due.to_s) if due.present?) || fallback_due,
                     digitable_line: (billet["barcode"] || data["barcode"]).presence)
        end

        # Na emissão `payment` é só o nome do meio ("banking_billet"); na consulta é um objeto com o boleto dentro.
        def nested_billet(data)
          payment = data["payment"]
          payment["banking_billet"] if payment.is_a?(Hash) && payment["banking_billet"].is_a?(Hash)
        end

        def find_pdf_url(data)
          candidates = [ data.dig("pdf", "charge"), nested_billet(data)&.dig("pdf", "charge") ]
          candidates.find(&:present?)
        end

        def pix_issued(data, txid)
          status = Payloads::PIX_STATUS[data["status"].to_s] or raise Error, I18n.t("payments.providers.efi.errors.unknown_status")
          amount = BigDecimal(data.dig("valor", "original").to_s.presence || "0") * 100
          payments = Array(data["pix"])
          paid = payments.sum { |pix| cents_of(pix["valor"]) }
          refunded = payments.sum { |pix| Array(pix["devolucoes"]).select { |refund| refund["status"].to_s == "DEVOLVIDO" }.sum { |refund| cents_of(refund["valor"]) } }
          Issued.new(external_id: (data["txid"] || txid).to_s, status: status, amount_cents: amount.to_i.nonzero?,
                     due_on: (Date.iso8601(data.dig("calendario", "dataDeVencimento").to_s) rescue nil), copy_paste: data["pixCopiaECola"].presence,
                     paid_cents: (paid.positive? ? paid : nil), refunded_cents: (refunded if payments.any?))
        end

        # "110.00" (reais, em texto) em centavos; nada válido = 0.
        def cents_of(value)
          (BigDecimal(value.to_s) * 100).round.to_i
        rescue ArgumentError, TypeError
          0
        end

        # A imagem do QR Code do fornecedor, se vier em PNG; SVG, falta de permissão ou qualquer falha deixam o QR Code a ser gerado aqui (IP-P3).
        def qr_png_of(account, loc_id)
          return if loc_id.blank?

          Payloads.png_from_data_uri(call(account, :pix, :get, "/v2/loc/#{escape(loc_id)}/qrcode")["imagemQrcode"])
        rescue Error
          nil
        end
    end
  end
end
