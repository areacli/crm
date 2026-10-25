# Nomes de fornecedor e de campo nas telas das contas de pagamento (12).
module PaymentAccountsHelper
  def provider_name(provider) = Payments::Providers.known?(provider) ? Payments::Providers.manifest(provider).label : provider

  # Rótulo do campo no histórico: o do manifesto, ou o nome da coluna quando não é campo do fornecedor.
  def account_field_label(account, field)
    return "—" if field.blank?
    return t("payments.accounts.fields.#{field}", default: field) unless account.provider_available? && (manifest_field = account.manifest.field(field))

    account.manifest.label_of(manifest_field)
  end
end
