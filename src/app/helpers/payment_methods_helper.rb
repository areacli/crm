# Textos da página "Meios de pagamento" (16, revisão 1, R373a a R373c): o acesso e o aviso de pagamento de cada integração, e o aviso da troca.
module PaymentMethodsHelper
  def modality_label(modality) = t("payments.accounts.modalities.#{modality}")

  # O meio no meio da frase ("deixa de emitir boleto"); o Pix continua com maiúscula.
  def modality_in_sentence(modality) = modality.to_s == "pix" ? modality_label(modality) : modality_label(modality).sub(/\A[[:upper:]]/, &:downcase)

  # Acesso: a conexão por autorização, o certificado com o vencimento, ou se as credenciais estão definidas (nunca o valor, R261).
  def account_access_line(account)
    return "—" unless account.provider_available?

    if Payments::Connection.authorization?(account)
      connected_at = account.config["connected_at"].presence
      Payments::Connection.connected?(account) && connected_at ? t("payments.methods.access.connected", date: date_br(Time.iso8601(connected_at).to_date)) : t("payments.methods.access.not_connected")
    elsif (expires_on = account.certificate_expires_on)
      t("payments.methods.access.certificate", date: date_br(expires_on))
    elsif account.fields.any? { |field| field.secret? && !field.generated && account.secret_set?(field.name) }
      t("payments.methods.access.credentials")
    else
      t("payments.methods.access.missing")
    end
  end

  # Aviso de pagamento: o endereço vai em cada cobrança, ou o webhook cadastrado no fornecedor (sem ele, o pagamento chega pela consulta, R284c).
  def account_notice_line(account)
    return "—" unless account.provider_available?
    return t("payments.methods.notice.per_charge") if Payments::WebhookUrl.per_charge?(account)
    return "—" unless account.modality.in?(%w[boleto pix])

    account.webhook_registered_at ? t("payments.methods.notice.registered", date: date_br(account.webhook_registered_at.to_date)) : t("payments.methods.notice.not_registered")
  end

  def account_last_test(account)
    return "Nunca testada" unless account.last_test_status

    "#{account.last_test_status == 'ok' ? 'Boa' : 'Falhou'}, #{datetime_br(account.last_tested_at)}"
  end

  # O que acontece na troca, dito antes de salvar (R373c).
  def replacement_warning(account)
    t("payments.methods.replace.warning", nickname: account.nickname, modality: modality_in_sentence(account.modality),
      environment: t("payments.accounts.environments.#{account.environment}").downcase,
      vigentes: t("payments.methods.replace.vigentes", count: account.instruments.where(open: true).count))
  end
end
