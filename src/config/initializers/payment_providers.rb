# Fornecedores de instrumentos de pagamento instalados (12, R258). Um fornecedor novo entra aqui e no seu adaptador, sem mexer no resto.
Rails.application.config.to_prepare do
  Payments::Providers.reset!
  Payments::Providers.register(:fake, "Payments::Providers::Fake")
  Payments::Providers.register(:efi, "Payments::Providers::Efi")
end
