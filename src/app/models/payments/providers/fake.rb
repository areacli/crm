module Payments
  module Providers
    # Fornecedor falso (12, R258): as três modalidades, em memória, com os formatos dos fornecedores reais. É o que a CI e a demonstração usam;
    # nenhum teste chama fornecedor real. O estado vive no processo (`Fake.reset!` o limpa) e nada é gravado.
    class Fake < Base
      include Boleto
      include Pix
      include Card

      # Menor PDF válido e menor PNG válido (1 pixel): bastam para exercitar guarda, SHA-256 e entrega.
      PDF = "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n".b.freeze
      PNG = [ "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360f8cfc00000030101003fc5a5b80000000049454e44ae426082" ].pack("H*").freeze

      MANIFEST = Manifest.new(
        provider: "fake",
        modalities: %w[boleto pix card],
        fields: [
          Manifest::Field.new(name: "api_key", type: :secret, required: true),
          Manifest::Field.new(name: "connection_result", type: :select, required: true, options: %w[ok refused unavailable], default: "ok"),
          Manifest::Field.new(name: "pix_key", type: :text, modalities: %w[pix], required: true, maxlength: 77),
          Manifest::Field.new(name: "certificate", type: :file, modalities: %w[pix], format: :pkcs12, password_field: "certificate_password"),
          Manifest::Field.new(name: "certificate_password", type: :secret, modalities: %w[pix]),
          Manifest::Field.new(name: "webhook_secret", type: :secret, generated: true),
          Manifest::Field.new(name: "expire_days", type: :number, modalities: %w[boleto pix], min: 1, max: 365, default: 5),
          Manifest::Field.new(name: "max_installments", type: :number, modalities: %w[card], min: 1, max: 12, default: 1)
        ],
        # Cartão: o falso tokeniza no próprio navegador, sem biblioteca nem domínio externo (módulo `payments/drivers/fake`).
        capabilities: { webhook_auth: %w[hmac], pdf: "file", qr: "image", batch_limit: nil,
                        card_checkout: { driver: "payments/drivers/fake", script: nil, hosts: { script: [], connect: [], frame: [], img: [] } } }
      )

      class << self
        def store = @store ||= { instruments: {}, sequence: 0, failures: {}, omit_qr: false }

        def reset! = @store = nil

        # Ganchos dos testes: a operação falha com o erro dado (`times`: quantas vezes; nil = sempre), e o Pix deixa de devolver a imagem do QR Code.
        def fail_on(operation, error, times: nil) = store[:failures][operation.to_sym] = { error: error, times: times }

        def omit_qr_image! = store[:omit_qr] = true

        # Ganchos dos testes da parte D: o que o fornecedor passa a dizer na consulta (pago, devolvido), sem avisar ninguém.
        def mark_paid!(external_id, paid_cents: nil) = store[:instruments].fetch(external_id).merge!(status: "paid", paid_cents: paid_cents)

        def mark_refunded!(external_id, cents) = store[:instruments].fetch(external_id)[:refunded_cents] = cents

        def mark_status!(external_id, status) = store[:instruments].fetch(external_id)[:status] = status
      end

      def manifest = MANIFEST

      def test_connection(account)
        case account.config["connection_result"]
        when "refused" then ConnectionResult.new(ok: false, message: I18n.t("payments.accounts.test.fake_refused"))
        when "unavailable" then raise Error, I18n.t("payments.accounts.test.fake_unavailable")
        else ConnectionResult.new(ok: true, message: I18n.t("payments.accounts.test.ok"))
        end
      end

      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        failure(:issue_boleto)
        remember(custom_id, kind: "boleto", amount_cents: amount_cents, due_on: due_on, digitable_line: digitable_line(amount_cents), pdf: PDF)
      end

      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {})
        failure(:issue_pix)
        remember(custom_id, kind: "pix", amount_cents: amount_cents, due_on: due_on, copy_paste: "00020126#{custom_id.to_s.ljust(10, '0')}5204000053039865802BR",
                            qr_png: (PNG unless self.class.store[:omit_qr]))
      end

      def download_boleto_pdf(account, external_id)
        failure(:download_boleto_pdf)
        super
      end

      def fetch_boleto(_account, external_id) = fetch(external_id)
      def fetch_pix(_account, external_id) = fetch(external_id)
      def fetch_card(_account, external_id) = fetch(external_id)

      def cancel_boleto(_account, external_id) = change(external_id, status: "canceled")
      def cancel_pix(_account, external_id) = change(external_id, status: "canceled")

      def change_boleto_due_date(_account, external_id, due_on) = change(external_id, due_on: due_on)

      def refund_pix(_account, external_id, amount_cents:, refund_id: nil) = refund(external_id, amount_cents)
      def refund_card(_account, external_id, amount_cents:) = refund(external_id, amount_cents)

      # Parcelas sem juros (o falso não cobra juros).
      def installments(_account, amount_cents:, brand: nil)
        (1..12).map { |count| InstallmentOption.new(installments: count, installment_cents: (amount_cents.to_f / count).ceil, total_cents: amount_cents, has_interest: false) }
      end

      # O token "recusado" simula a recusa do emissor por segurança (sem nova tentativa); "tente-depois" simula a recusa que pode ser repetida; qualquer
      # outro aprova. O falso guarda a cobrança pelo `custom_id`: repetir devolve a mesma.
      def charge_card(account, custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil)
        failure(:charge_card)
        refusal = { "recusado" => [ "security", false ], "tente-depois" => [ "try_later", true ], "dados-invalidos" => [ "invalid_data", true ] }[payment_token]
        instrument = remember(custom_id, kind: "card", amount_cents: amount_cents, status: refusal ? "declined" : "active", installments: installments, refusal: refusal)
        record = self.class.store[:instruments].fetch(instrument.external_id)
        code, retry_flag = record[:refusal]
        CardResult.new(external_id: instrument.external_id, status: code ? "declined" : "approved", amount_cents: amount_cents, installments: record[:installments], refusal_code: code,
                       retry: retry_flag || false, refusal_reason: (code ? "Recusa simulada (#{code})" : nil))
      end

      def card_checkout_config(_account) = {}

      # Aviso do falso: JSON { "id", "type" (paid, refunded, canceled, expired, other), "external_id", "amount_cents" }, autenticado pelo cabeçalho X-Signature
      # (HMAC do corpo com o segredo da conta, atual ou anterior na vigência dupla). `{"batch": [...]}` traz vários avisos.
      def parse_notification(account, body:, headers:, context: {})
        signature = headers["X-Signature"].to_s
        valid = account.webhook_secrets.any? do |secret|
          expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
          signature.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.fixed_length_secure_compare(signature, expected)
        end
        raise InvalidSignature, I18n.t("payments.accounts.test.bad_signature") unless valid

        data = JSON.parse(body)
        (data["batch"] || [ data ]).map do |item|
          Notification.new(event_id: item.fetch("id"), kind: item.fetch("type"), external_id: item["external_id"], amount_cents: item["amount_cents"], occurred_at: Time.current)
        end
      rescue JSON::ParserError, KeyError, TypeError
        raise Error, I18n.t("payments.accounts.test.bad_payload")
      end

      private
        def failure(operation)
          entry = self.class.store[:failures][operation] or return
          if entry[:times]
            self.class.store[:failures].delete(operation) if (entry[:times] -= 1) <= 0
          end
          raise entry[:error]
        end

        def remember(custom_id, attributes)
          store = self.class.store
          existing = store[:instruments].values.find { |instrument| instrument[:custom_id] == custom_id }
          return issued(existing) if existing

          store[:sequence] += 1
          external_id = "FAKE-#{attributes[:kind].upcase}-#{store[:sequence]}"
          instrument = { custom_id: custom_id, external_id: external_id, status: "active" }.merge(attributes)
          store[:instruments][external_id] = instrument
          issued(instrument)
        end

        def fetch(external_id)
          failure(:fetch)
          issued(self.class.store[:instruments].fetch(external_id) { raise Error, I18n.t("payments.accounts.test.not_found") })
        end

        def change(external_id, attributes) = issued(self.class.store[:instruments].fetch(external_id) { raise Error, I18n.t("payments.accounts.test.not_found") }.merge!(attributes))

        def refund(external_id, amount_cents)
          instrument = self.class.store[:instruments].fetch(external_id) { raise Error, I18n.t("payments.accounts.test.not_found") }
          raise Error, I18n.t("payments.accounts.test.refund_too_high") if amount_cents > instrument[:amount_cents]

          instrument[:refunded_cents] = instrument.fetch(:refunded_cents, 0) + amount_cents
          issued(instrument)
        end

        def issued(instrument)
          paid = instrument[:status] == "paid" ? (instrument[:paid_cents] || instrument[:amount_cents]) : nil
          Issued.new(external_id: instrument[:external_id], status: instrument[:status], amount_cents: instrument[:amount_cents], due_on: instrument[:due_on],
                     digitable_line: instrument[:digitable_line], copy_paste: instrument[:copy_paste], pdf: instrument[:pdf], qr_png: instrument[:qr_png],
                     paid_cents: paid, refunded_cents: instrument[:refunded_cents])
        end

        # 47 dígitos no formato das linhas digitáveis (5.5 5.6 5.6 1 14); o valor entra nos dez últimos.
        def digitable_line(amount_cents)
          digits = "3419#{'1' * 25}#{amount_cents.to_s.rjust(14, '0')}"[0, 47].ljust(47, "0")
          "#{digits[0, 5]}.#{digits[5, 5]} #{digits[10, 5]}.#{digits[15, 6]} #{digits[21, 5]}.#{digits[26, 6]} #{digits[32]} #{digits[33, 14]}"
        end
    end
  end
end
