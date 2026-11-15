module Payments
  module Providers
    # Bradesco, o segundo fornecedor real (12, revisão 4; plano do adaptador, decisões BR1 a BR11). Fonte: os manuais do banco
    # (API Pix Recebimento 2.6.1, versão 08; API de Cobrança 1.6.4), lidos campo a campo; o que eles contradizem fica no roteiro de homologação
    # (docs/homologacao-bradesco.md) e, aqui, o código segue o exemplo do manual e diz isso no comentário.
    #
    # Pix: padrão do Banco Central (`PixBcb`), com token por formulário, Basic e mTLS, ligado ao certificado; emissão por `PUT /v2/cobv-emv/{txid}`, que
    # devolve o "copia e cola" e a imagem (não há `GET /loc/{id}/qrcode`). Boleto: API própria de cobrança, com o nosso número do CRM (BR2), a ficha de
    # compensação gerada aqui (BR1) e a autenticação atrás de `BoletoAuth` (o manual não a traz: bloqueio B1). Os dois com webhook e lista de pagos (BR3, BR4).
    # O cliente HTTP é injetável (`Bradesco.http_client=`): nenhum teste chama o Bradesco. Segredos só durante a chamada, nunca em log nem mensagem.
    class Bradesco < Base
      include Boleto
      include Pix

      FIELDS = [
        Manifest::Field.new(name: "client_id", type: :secret, modalities: %w[pix], required: true),
        Manifest::Field.new(name: "client_secret", type: :secret, modalities: %w[pix], required: true),
        Manifest::Field.new(name: "certificate", type: :file, modalities: %w[pix], required: true, format: :pkcs12, password_field: "certificate_password"),
        Manifest::Field.new(name: "certificate_password", type: :secret, modalities: %w[pix]),
        Manifest::Field.new(name: "pix_key", group: :access, type: :text, modalities: %w[pix], required: true, maxlength: 77),
        Manifest::Field.new(name: "qr_name", type: :text, modalities: %w[pix], maxlength: 15),
        # Boleto: beneficiário e contrato de cobrança, como o banco os tem (a ficha imprime a razão social e o CNPJ iguais aos do cadastro do banco).
        Manifest::Field.new(name: "beneficiary_name", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 100),
        Manifest::Field.new(name: "beneficiary_document", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 14),
        Manifest::Field.new(name: "agency", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 4),
        Manifest::Field.new(name: "agency_digit", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 1),
        Manifest::Field.new(name: "account_number", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 7),
        Manifest::Field.new(name: "account_digit", group: :access, type: :text, modalities: %w[boleto], required: true, maxlength: 1),
        Manifest::Field.new(name: "wallet", group: :access, type: :number, modalities: %w[boleto], required: true, min: 1, max: 99, default: 9),
        Manifest::Field.new(name: "species", type: :select, modalities: %w[boleto], required: true, options: Bradesco::Payloads::SPECIES.keys, default: "DM"),
        Manifest::Field.new(name: "our_number_start", group: :access, type: :number, modalities: %w[boleto], required: true, min: 1, max: 99_999_999_999),
        Manifest::Field.new(name: "webhook_secret", type: :secret, generated: true),
        Manifest::Field.new(name: "expire_days", type: :number, modalities: %w[boleto pix], min: 1, max: 365, default: 5),
        Manifest::Field.new(name: "fine_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 10, default: 2),
        Manifest::Field.new(name: "interest_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 10, default: 1),
        Manifest::Field.new(name: "discount_percent", type: :number, modalities: %w[boleto pix], min: 0, max: 100, default: 0),
        Manifest::Field.new(name: "write_off_days", type: :number, modalities: %w[boleto], min: 0, max: 120, default: 30),
        Manifest::Field.new(name: "message", type: :text, modalities: %w[boleto], maxlength: 80)
      ].freeze

      # `pdf: "generated"`: a ficha é desenhada aqui (R284e). `our_number`: o CRM reserva o nosso número de 11 dígitos (R284f). `paid_list`: Pix a cada
      # 10 minutos; boleto às 7h20, porque a lista de liquidados é do dia anterior (BR11). `quiet_hours`: a API de cobrança pode estar fora das 00h às
      # 03h (manual de cobrança, l. 2159-2160; BR7). `webhook_url_max`: o cadastro do webhook de boleto aceita 100 caracteres (`urlEnvio`, R284g).
      CAPABILITIES = { webhook_auth: %w[hmac mtls], pdf: "generated", qr: "image", batch_limit: nil, our_number: { digits: 11 },
                       paid_list: { "pix" => { every: 10 }, "boleto" => { daily_at: "07:20" } }, quiet_hours: { "boleto" => "00:00-03:00" },
                       webhook_url_max: 100 }.freeze

      PIX_HOSTS = { "production" => "https://qrpix.bradesco.com.br", "sandbox" => "https://qrpix-h.bradesco.com.br" }.freeze
      BOLETO_HOSTS = { "production" => "https://openapi.bradesco.com.br", "sandbox" => "https://openapisandbox.prebanco.com.br" }.freeze
      # O manual escreve o caminho da devolução com acento (`/pix/{e2eid}/devolução/{id}`, P l. 8009); o padrão do Banco Central é sem. Vai sem, e a
      # homologação confirma (item do roteiro).
      REFUND_SEGMENT = "devolucao".freeze

      class << self
        def http_client = (@http_client ||= HttpClient.new)

        attr_writer :http_client

        # Autenticação da API de cobrança (B1): sem o documento do banco, a peça padrão recusa toda chamada.
        def boleto_auth = (@boleto_auth ||= BoletoAuth::Unconfigured.new)

        attr_writer :boleto_auth
      end

      # O boleto só entra no cadastro quando a autenticação da API de cobrança existe (R284j); até lá, o Bradesco oferece só Pix.
      def manifest
        modalities = self.class.boleto_auth.configured? ? %w[boleto pix] : %w[pix]
        Manifest.new(provider: "bradesco", modalities: modalities, fields: FIELDS, capabilities: CAPABILITIES)
      end

      def modalities = manifest.modalities

      def test_connection(account)
        if account.modality == "pix"
          pix_token(account)
        else
          # Consultar um nosso número que não existe prova a autenticação e o contrato: o banco responde "título inexistente" (CBTT0552).
          boleto_call(account, :post, "/boleto/cobranca-consulta/v1/consultar", Payloads.lookup_body(account, "0"), not_found_ok: true)
        end
        ConnectionResult.new(ok: true, message: I18n.t("payments.accounts.test.ok"))
      rescue NetworkError => error
        raise Error, error.message
      rescue Error => error
        ConnectionResult.new(ok: false, message: error.message)
      end

      # ---- Avisos (R281, R284b) ----

      # Pix: `pix[]` do padrão. Boleto: o aviso de pagamento do manual de cobrança (campos em texto, `tipoEvento` "P"). Os dois autenticados pelo
      # `hmac` da URL (BR5), ou pelo certificado de cliente verificado pelo proxy quando a instalação confia no cabeçalho; o manual não descreve outra
      # autenticação. Corpo sem nada reconhecível devolve lista vazia.
      def parse_notification(account, body:, headers:, context: {})
        data = parse_body(body)
        notifications = if data["pix"].is_a?(Array)
          data["pix"].flat_map { |pix| PixBcb.received_notifications(pix) }
        elsif data["tipoEvento"].present? && data["nossoNumero"].present?
          Array(Payloads.boleto_paid_notification(data))
        else
          []
        end
        authenticate!(account, context) if notifications.any? || data["pix"].is_a?(Array)
        notifications
      end

      # Cadastra a URL do webhook: Pix por chave (`PUT /v2/webhook/{chave}`); boleto pela API de cobrança (inclusão, aviso de pagamento). Devolve a URL.
      def register_webhook(account)
        url = WebhookUrl.for(account) or raise Error, I18n.t("payments.webhook_registration.no_url")
        if account.modality == "pix"
          key = account.config["pix_key"].presence or raise Error, I18n.t("payments.providers.bradesco.errors.no_pix_key")
          pix_call(account, :put, "/v2/webhook/#{escape(key)}", body: { "webhookUrl" => url })
        else
          raise Error, I18n.t("payments.webhook_registration.too_long", max: CAPABILITIES[:webhook_url_max]) if url.length > CAPABILITIES[:webhook_url_max]

          path = account.environment == "production" ? "/boleto/cobranca-webhook/v1/executar" : "/boleto/cobranca-webhook/v1/cadastrar"
          boleto_call(account, :post, path, Payloads.webhook_body(account, url))
        end
        url
      end

      # Lista de pagos (R284c): Pix recebidos (`GET /v2/pix`) ou boletos liquidados (lista D-1, de 50 em 50), com o mesmo identificador do webhook.
      def list_paid(account, from:, to:)
        account.modality == "pix" ? list_pix(account, from: from, to: to) : list_liquidated(account, from: from, to: to)
      end

      # ---- Pix ----

      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        key = account.config["pix_key"].presence or raise Error, I18n.t("payments.providers.bradesco.errors.no_pix_key")
        # O desconto do Bradesco vai até a véspera: o manual pede data menor que o vencimento (P l. 4210-4211).
        body = PixBcb.cobv_body(amount_cents: amount_cents, due_on: due_on, payer: payer, pix_key: key, options: options, discount_until: due_on - 1)
        body["nomePersonalizacaoQr"] = account.config["qr_name"].to_s.first(15) if account.config["qr_name"].present?
        data = idempotent { pix_call(account, :put, "/v2/cobv-emv/#{escape(custom_id)}", body: body, conflict: true) }
        return fetch_pix(account, custom_id) if data == :conflict

        cobv = data["cobv"].is_a?(Hash) ? data["cobv"] : data
        issued = pix_issued(cobv.merge("pixCopiaECola" => data["emv"].presence || cobv["pixCopiaECola"]), custom_id)
        issued.with(qr_png: Payloads.png_of(data["base64"]))
      end

      def fetch_pix(account, external_id)
        data = idempotent { pix_call(account, :get, "/v2/cobv/#{escape(external_id)}") }
        raise Error, I18n.t("payments.providers.bradesco.errors.not_found") if data.empty?

        pix_issued(data, external_id)
      end

      # Cancelar é mandar só o estado (o Bradesco recusa o cancelamento junto com outra mudança, P l. 2392-2394).
      def cancel_pix(account, external_id)
        data = idempotent { pix_call(account, :patch, "/v2/cobv/#{escape(external_id)}", body: { "status" => PixBcb::CANCELED }) }
        data.empty? ? Issued.new(external_id: external_id, status: "canceled", amount_cents: nil) : pix_issued(data, external_id)
      end

      def refund_pix(account, external_id, amount_cents:, refund_id: nil)
        paid = idempotent { pix_call(account, :get, "/v2/cobv/#{escape(external_id)}") }
        end_to_end_id = Array(paid["pix"]).first&.dig("endToEndId").presence or raise Error, I18n.t("payments.providers.bradesco.errors.pix_not_paid")
        refund_id ||= Digest::SHA256.hexdigest("#{external_id}:#{amount_cents}")[0, 32].upcase
        idempotent { pix_call(account, :put, "/v2/pix/#{escape(end_to_end_id)}/#{REFUND_SEGMENT}/#{escape(refund_id)}", body: { "valor" => PixBcb.decimal(amount_cents) }) }
        Issued.new(external_id: external_id, status: "paid", amount_cents: amount_cents)
      end

      # ---- Boleto ----

      # Registro com o nosso número reservado pelo Issuer (R284f). "Título já cadastrado" (69) consulta o título e só segue se valor, vencimento e
      # pagador conferem com o pedido.
      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        our_number = options[:our_number].presence or raise Error, I18n.t("payments.providers.bradesco.errors.no_our_number")
        body = Payloads.registration_body(account, our_number: our_number, custom_id: custom_id, amount_cents: amount_cents, due_on: due_on, payer: payer, options: options)
        data = boleto_call(account, :post, "/boleto/cobranca-registro/v1/cobranca", body, registration: true)
        return confirm_registered(account, our_number, amount_cents: amount_cents, due_on: due_on, payer: payer) if data == :already_registered

        Payloads.registration_issued(data, our_number: our_number, fallback_amount: amount_cents, fallback_due: due_on)
      end

      def fetch_boleto(account, external_id)
        Payloads.lookup_issued(boleto_call(account, :post, "/boleto/cobranca-consulta/v1/consultar", Payloads.lookup_body(account, external_id)), external_id)
      end

      # Baixa com o código 57 ("conforme seu pedido"). Repetida, o banco recusa pela situação do título: a consulta decide se já está baixado.
      def cancel_boleto(account, external_id)
        boleto_call(account, :post, "/boleto/cobranca-baixa/v1/baixar", Payloads.write_off_body(account, external_id))
        Issued.new(external_id: external_id, status: "canceled", amount_cents: nil)
      rescue Error => error
        raise if error.is_a?(NetworkError)

        fetched = fetch_boleto(account, external_id)
        raise error unless fetched.status == "canceled"

        fetched
      end

      # A alteração não devolve a linha digitável nova (C l. 2650-2654): consulta logo depois, porque o fator de vencimento muda.
      def change_boleto_due_date(account, external_id, due_on)
        boleto_call(account, :put, "/boleto/cobranca-altera/v1/alterar", Payloads.due_date_body(account, external_id, due_on))
        fetch_boleto(account, external_id)
      end

      # A ficha de compensação é desenhada aqui (R284e), da linha digitável que a consulta devolve, conferida contra o vencimento e o valor do título.
      def download_boleto_pdf(account, external_id)
        issued = fetch_boleto(account, external_id)
        instrument = PaymentInstrument.find_by(account_id: account.id, external_id: external_id)
        BoletoSlip.new(**Payloads.slip_attributes(account, issued, instrument)).render
      rescue Febraban::Invalid => error
        raise Error, I18n.t("payments.providers.bradesco.errors.slip_invalid", detail: error.message)
      end

      private
        # ---- Pix: chamadas ----

        def pix_call(account, method, path, body: nil, retried: false, conflict: false)
          token = pix_token(account)
          headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
          headers["Content-Type"] = "application/json" if body
          response = self.class.http_client.request(method, PIX_HOSTS.fetch(account.environment) + path, headers: headers, body: body&.to_json, tls: tls_for(account))
          if response.status == 401 && !retried
            TokenStore.forget(pix_token_key(account))
            return pix_call(account, method, path, body: body, retried: true, conflict: conflict)
          end
          return :conflict if conflict && response.status == 412 && Payloads.txid_in_use?(response.body)

          read_pix(response)
        end

        def read_pix(response)
          return {} if response.status == 204 || response.body.to_s.strip.empty? && (200..299).cover?(response.status)

          json = (JSON.parse(response.body) rescue nil)
          return json || raise(Error, I18n.t("payments.providers.bradesco.errors.unexpected")) if (200..299).cover?(response.status)

          message = PixBcb.error_message(json)
          case response.status
          when 401, 403 then raise Error, I18n.t("payments.providers.bradesco.errors.refused", detail: message)
          when 429, 503, 504 then raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: true)
          when 500..599 then raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: false)
          else raise Error, I18n.t("payments.providers.bradesco.errors.refused", detail: message)
          end
        end

        # O Pix pelo `txid` nosso é idempotente: qualquer falha de rede pode ser repetida sem duplicar.
        def idempotent
          yield
        rescue NetworkError => error
          raise NetworkError.new(error.message, retry_safe: true)
        end

        # Token por formulário, com o Client ID e o Secret em Basic e a conexão mTLS com o certificado (P l. 310-334). O token é ligado ao certificado
        # (RFC 8705): a chave do guardador inclui o resumo do certificado, e trocar o certificado pede token novo.
        def pix_token(account)
          TokenStore.fetch(pix_token_key(account)) do
            client_id = account.secrets["client_id"].presence
            client_secret = account.secrets["client_secret"].presence
            raise Error, I18n.t("payments.providers.bradesco.errors.no_credentials") unless client_id && client_secret

            response = self.class.http_client.request(:post, PIX_HOSTS.fetch(account.environment) + "/oauth/token", body: "grant_type=client_credentials", tls: tls_for(account),
                                                       headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}",
                                                                  "Content-Type" => "application/x-www-form-urlencoded" })
            json = (JSON.parse(response.body) rescue {})
            token = json["access_token"] if response.status == 200
            raise Error, I18n.t("payments.providers.bradesco.errors.credential_refused") if [ 400, 401, 403 ].include?(response.status) || (response.status == 200 && token.blank?)
            raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: true) unless response.status == 200

            [ token, json["expires_in"].presence || 300 ]
          end
        end

        def pix_token_key(account)
          Digest::SHA256.hexdigest([ "bradesco-pix", account.environment, account.secrets["client_id"], account.secrets["client_secret"],
                                     Digest::SHA256.hexdigest(account.secrets["certificate"].to_s) ].join("|"))
        end

        # Certificado e chave do .p12 da integração, abertos agora e só na memória desta chamada.
        def tls_for(account)
          encoded = account.secrets["certificate"].presence or raise Error, I18n.t("payments.providers.bradesco.errors.no_certificate")
          pkcs12 = OpenSSL::PKCS12.new(Base64.strict_decode64(encoded), account.secrets["certificate_password"].to_s)
          { cert: pkcs12.certificate, key: pkcs12.key }
        rescue OpenSSL::PKCS12::PKCS12Error, ArgumentError
          raise Error, I18n.t("payments.providers.bradesco.errors.certificate_unreadable")
        end

        def pix_issued(data, txid) = PixBcb.issued(data, txid, unknown_status_message: I18n.t("payments.providers.bradesco.errors.unknown_status"))

        def list_pix(account, from:, to:)
          page = 0
          notifications = []
          loop do
            data = idempotent { pix_call(account, :get, "/v2/pix?#{PixBcb.received_list_query(from: from, to: to, page: page)}") }
            notifications.concat(Array(data["pix"]).flat_map { |pix| PixBcb.received_notifications(pix) })
            break unless PixBcb.more_pages?(data, page)

            page += 1
          end
          notifications
        end

        # ---- Boleto: chamadas ----

        # Chamada à API de cobrança, com a autenticação de `BoletoAuth` (sem o documento do banco, recusa antes de sair qualquer dado, R284j).
        # `registration`: lê a resposta do registro (códigos próprios, 69 = já cadastrado). `not_found_ok`: "título inexistente" é resposta esperada.
        def boleto_call(account, method, path, body, registration: false, not_found_ok: false)
          json = body.to_json
          auth = self.class.boleto_auth
          headers = { "Accept" => "application/json", "Content-Type" => "application/json" }.merge(auth.headers(account, method: method, path: path, body: json))
          response = self.class.http_client.request(method, BOLETO_HOSTS.fetch(account.environment) + path, headers: headers, body: json, tls: auth.tls(account))
          Payloads.read_boleto(response, registration: registration, not_found_ok: not_found_ok)
        end

        # Repetição depois de "título já cadastrado": o título com o nosso número tem de ser o que pedimos, senão o número foi usado por outro.
        def confirm_registered(account, our_number, amount_cents:, due_on:, payer:)
          fetched = fetch_boleto(account, our_number)
          same = fetched.amount_cents == amount_cents && fetched.due_on == due_on
          raise Error, I18n.t("payments.providers.bradesco.errors.our_number_taken", number: our_number) unless same

          fetched
        end

        # Liquidados por data de pagamento, de `from` a `to` (no máximo 60 dias, C l. 3789), de 50 em 50.
        def list_liquidated(account, from:, to:)
          page = 0
          notifications = []
          loop do
            data = boleto_call(account, :post, "/boleto/cobranca-lista/v1/listar", Payloads.liquidated_list_body(account, from: from.to_date, to: to.to_date, page: page))
            notifications.concat(Array(data["titulos"]).filter_map { |title| Payloads.liquidated_notification(title) })
            break unless Payloads.more_pages?(data)

            page = (data["pagina"] || data["Pagina"]).to_i
          end
          notifications
        end

        # ---- Comuns ----

        def authenticate!(account, context)
          return if Rails.configuration.x.payments.trust_mtls_header && context[:client_verified]
          raise InvalidSignature, I18n.t("payments.providers.bradesco.errors.bad_webhook_auth") unless WebhookUrl.valid?(account, context.dig(:query, "hmac"))
        end

        def parse_body(body)
          text = body.to_s.strip
          return {} if text.empty?

          parsed = JSON.parse(text)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          raise Error, I18n.t("payments.accounts.test.bad_payload")
        end

        def escape(value) = ERB::Util.url_encode(value.to_s)
    end
  end
end
