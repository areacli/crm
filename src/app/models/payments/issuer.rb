module Payments
  # Emissão de boleto e Pix (12, R271 a R276). Só por serviço (console, testes, o futuro disparador): o back office não tem tela de emissão (R270).
  #
  # `request` grava o instrumento `emitting` com o nosso `custom_id` (repetir o pedido com o mesmo `custom_id` devolve o mesmo instrumento, R272) e
  # enfileira `IssueInstrumentJob` (fila `default`); `perform` é o trabalho do job: chama o fornecedor da conta ativa, baixa o PDF daqui (ou gera
  # o QR Code daqui), confere o SHA-256 do que guardou e passa a `active`. Falha vira `failed` com motivo. Só o erro de rede é tentado de novo, e só
  # quando a repetição não pode duplicar (o Pix pelo `txid` nosso; o boleto quando a conexão nem chegou a sair).
  class Issuer
    class Refused < StandardError; end
    class NoAccount < Refused; end

    MAX_ATTEMPTS = 5
    ACCOUNT_OPTION_KEYS = %w[fine_percent interest_percent discount_percent write_off_days message].freeze

    # Pedidos por minuto de um lote (limite de taxa para respeitar o consumo do fornecedor, IP-P7). Configurável: `config.x.payments.issue_per_minute`
    # (ou PAYMENTS_ISSUE_PER_MINUTE); o fornecedor pode impor um limite menor no manifesto (`batch_limit`).
    def self.per_minute = Rails.configuration.x.payments.issue_per_minute

    # `customer`: o pagador (nome, documento e endereço são copiados na emissão). `reference`: [tipo, número] opaco do objeto cobrado.
    def request(**attributes)
      instrument = build(**attributes)
      IssueInstrumentJob.perform_later(instrument.id) if instrument.state_emitting? && instrument.attempts.zero? && instrument.previously_new_record?
      instrument
    end

    # Lote: um job por instrumento, espaçados pelo limite de taxa (instrumento que já existia não é enfileirado de novo).
    def request_batch(requests, per_minute: nil)
      interval = 60.0 / [ per_minute || self.class.per_minute, 1 ].max
      requests.each_with_index.map do |attributes, index|
        instrument = build(**attributes)
        IssueInstrumentJob.set(wait: (index * interval).seconds).perform_later(instrument.id) if instrument.previously_new_record?
        instrument
      end
    end

    # O trabalho do job. Idempotente: instrumento que já saiu de `emitting` não é tocado; o que já tem identificador externo só completa os arquivos.
    def perform(instrument)
      return instrument unless instrument.state_emitting?

      instrument.increment!(:attempts)
      return instrument unless payer_valid?(instrument)

      account = instrument.account
      return instrument.tap { |i| i.fail!(I18n.t("payments.instruments.account_unavailable")) } unless account.active? && account.provider_available?

      adapter = account.adapter
      issued = instrument.external_id.present? ? nil : issue(instrument, adapter)
      complete(instrument, adapter, issued)
      instrument
    rescue Providers::NetworkError => error
      raise if retry?(instrument, error)

      instrument.fail!(I18n.t("payments.instruments.network_failed", detail: error.message))
      instrument
    rescue Providers::Error => error
      instrument.fail!(error.message)
      instrument
    end

    # R276: cancelar é chamada ao fornecedor; o pago nunca se cancela, e só o ativo se cancela.
    def cancel(instrument)
      instrument.with_lock do
        raise Refused, I18n.t("payments.instruments.paid_untouchable") if instrument.final?
        raise Refused, I18n.t("payments.instruments.not_cancelable") unless instrument.cancelable?

        adapter = instrument.account.adapter
        instrument.boleto? ? adapter.cancel_boleto(instrument.account, instrument.external_id) : adapter.cancel_pix(instrument.account, instrument.external_id)
        instrument.update!(state: "canceled")
      end
      instrument
    end

    # Só boleto ativo e só para uma data futura; o PDF é baixado de novo (a ficha leva o vencimento novo).
    def change_due_date(instrument, due_on)
      raise Refused, I18n.t("payments.instruments.paid_untouchable") if instrument.final?
      raise Refused, I18n.t("payments.instruments.due_date_boleto_only") unless instrument.boleto?
      raise Refused, I18n.t("payments.instruments.not_cancelable") unless instrument.cancelable?
      raise Refused, I18n.t("payments.instruments.due_date_past") unless due_on > Date.current

      instrument.account.adapter.change_boleto_due_date(instrument.account, instrument.external_id, due_on)
      instrument.update!(due_on: due_on)
      refresh_files(instrument)
    end

    # Baixa de novo o PDF de um boleto ativo (depois de mudar o vencimento, ou se a primeira baixa falhou).
    def refresh_files(instrument)
      return instrument unless instrument.boleto? && instrument.state_active?

      instrument.boleto_pdf.purge
      store(instrument, :boleto_pdf, instrument.account.adapter.download_boleto_pdf(instrument.account, instrument.external_id), "application/pdf", "pdf")
      instrument.update!(failure_reason: nil)
      instrument
    rescue Providers::Error => error
      instrument.update!(failure_reason: I18n.t("payments.instruments.pdf_outdated", detail: error.message).truncate(300))
      raise
    end

    private
      # Grava o instrumento `emitting`; com o mesmo `custom_id` devolve o que já existe (R272).
      def build(tenant:, kind:, amount_cents:, customer:, due_on: nil, custom_id: nil, environment: "production", reference: nil, options: {})
        custom_id ||= SecureRandom.alphanumeric(32)
        existing = PaymentInstrument.find_by(tenant_id: tenant.id, custom_id: custom_id)
        return existing if existing

        account = tenant.payment_accounts.active.find_by(modality: kind.to_s, environment: environment.to_s) or
          raise NoAccount, I18n.t("payments.instruments.no_account", kind: I18n.t("payments.accounts.modalities.#{kind}"))
        due_on ||= Date.current + account.config.fetch("expire_days", 5).to_i
        PaymentInstrument.create!(tenant: tenant, account: account, provider: account.provider, customer: customer, kind: kind.to_s, amount_cents: amount_cents,
                                  due_on: due_on, custom_id: custom_id, reference_type: reference&.first&.to_s, reference_id: reference&.last,
                                  response_summary: { "options" => options.stringify_keys.slice(*ACCOUNT_OPTION_KEYS, "description") }, **Payer.snapshot(customer))
      rescue ActiveRecord::RecordNotUnique
        PaymentInstrument.find_by!(tenant_id: tenant.id, custom_id: custom_id)
      end

      # R274: sem CPF/CNPJ válido do pagador não há emissão nem chamada ao fornecedor.
      def payer_valid?(instrument)
        return true if instrument.payer_document.present? && Document.problem(instrument.payer_document).nil?

        instrument.fail!(I18n.t(instrument.payer_document.blank? ? "payments.instruments.payer_document_missing" : "payments.instruments.payer_document_invalid"))
        false
      end

      def issue(instrument, adapter)
        account = instrument.account
        options = account_defaults(account).merge(instrument.response_summary.fetch("options", {}).symbolize_keys)
        options = options.merge(notification_url: WebhookUrl.for(account)).compact # onde o fornecedor avisa o pagamento (parte D)
        payer = { name: instrument.payer_name, document: instrument.payer_document, address: instrument.payer_address }
        arguments = { custom_id: instrument.custom_id, amount_cents: instrument.amount_cents, due_on: instrument.due_on, payer: payer, options: options }
        issued = instrument.boleto? ? adapter.issue_boleto(account, **arguments) : adapter.issue_pix(account, **arguments)
        raise Providers::Error, I18n.t("payments.instruments.no_identifier") if issued.external_id.blank?

        # Guarda já o que o fornecedor devolveu: se a baixa do arquivo falhar e o job repetir, o instrumento não é emitido de novo.
        instrument.update!(external_id: issued.external_id, digitable_line: issued.digitable_line, copy_paste: issued.copy_paste, issued_at: Time.current,
                           response_summary: instrument.response_summary.except("options").merge("status" => issued.status, "total_cents" => issued.amount_cents,
                                                                                                 "due_on" => issued.due_on&.iso8601).compact)
        issued
      end

      def complete(instrument, adapter, issued)
        account = instrument.account
        if instrument.boleto?
          raise Providers::Error, I18n.t("payments.instruments.no_digitable_line") if instrument.digitable_line.blank?

          bytes = issued&.pdf || adapter.download_boleto_pdf(account, instrument.external_id)
          raise Providers::Error, I18n.t("payments.instruments.pdf_invalid") unless bytes.to_s.b.start_with?("%PDF")

          store(instrument, :boleto_pdf, bytes, "application/pdf", "pdf")
        else
          raise Providers::Error, I18n.t("payments.instruments.no_copy_paste") if instrument.copy_paste.blank?

          store(instrument, :pix_qr_png, issued&.qr_png || QrCode.png(instrument.copy_paste), "image/png", "png")
        end
        state = issued&.status.presence_in(%w[active paid expired canceled]) || "active"
        instrument.update!(state: state, failure_reason: nil)
      end

      # Guarda o arquivo no disco e confere, lendo de volta, que o SHA-256 é o do que veio (R273).
      def store(instrument, attachment, bytes, content_type, extension)
        bytes = bytes.to_s.b
        sha = Digest::SHA256.hexdigest(bytes)
        instrument.public_send(attachment).attach(io: StringIO.new(bytes), filename: "#{instrument.kind}-#{instrument.custom_id}.#{extension}", content_type: content_type, identify: false)
        unless Digest::SHA256.hexdigest(instrument.public_send(attachment).download) == sha
          instrument.public_send(attachment).purge
          raise Providers::Error, I18n.t("payments.instruments.hash_mismatch")
        end
        instrument.update!(attachment == :boleto_pdf ? { boleto_pdf_sha256: sha } : { pix_qr_sha256: sha })
      end

      def account_defaults(account)
        account.config.slice(*ACCOUNT_OPTION_KEYS).symbolize_keys
      end

      # Repetir só o que não duplica (R272) e só até o limite de tentativas.
      def retry?(instrument, error)
        (error.retry_safe || instrument.pix?) && instrument.attempts < MAX_ATTEMPTS
      end
  end
end
