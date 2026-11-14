# Nomes de fornecedor e de campo nas telas das contas de pagamento (12).
module PaymentAccountsHelper
  def provider_name(provider) = Payments::Providers.known?(provider) ? Payments::Providers.manifest(provider).label : provider

  # Rótulo do campo no histórico: o do manifesto, ou o nome da coluna quando não é campo do fornecedor.
  # Estado da conexão por autorização (12, revisão 5, R284k), em palavras.
  def connection_state(account)
    provider = account.manifest.label
    if Payments::Connection.connected?(account)
      date = date_br(Time.iso8601(account.config["connected_at"]).to_date) if account.config["connected_at"].present?
      label = account.config["connection_label"].presence
      label ? t("payments.connection.connected_as", date: date, label: label) : t("payments.connection.connected", date: date)
    elsif account.config["disconnected_at"].present?
      t("payments.connection.lost", date: date_br(Time.iso8601(account.config["disconnected_at"]).to_date))
    else
      t("payments.connection.never", provider: provider)
    end
  end

  def account_field_label(account, field)
    return "—" if field.blank?
    return t("payments.accounts.fields.#{field}", default: field) unless account.provider_available? && (manifest_field = account.manifest.field(field))

    account.manifest.label_of(manifest_field)
  end
end
