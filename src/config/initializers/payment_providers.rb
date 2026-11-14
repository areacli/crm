# Fornecedores de instrumentos de pagamento instalados (12, R258). Um fornecedor novo entra aqui e no seu adaptador, sem mexer no resto.
Rails.application.config.to_prepare do
  Payments::Providers.reset!
  Payments::Providers.register(:fake, "Payments::Providers::Fake")
  # Na demonstração só existe o fornecedor falso: nenhuma conta nem chamada a fornecedor real.
  Payments::Providers.register(:efi, "Payments::Providers::Efi") unless Demo.enabled?
  # Bradesco (12, revisão 4): Pix e, quando a autenticação da API de cobrança existir (bloqueio B1), boleto.
  Payments::Providers.register(:bradesco, "Payments::Providers::Bradesco") unless Demo.enabled?
  # PagBank (12, revisão 5): boleto, Pix e cartão cifrado no navegador, com a conexão por autorização (Connect).
  Payments::Providers.register(:pagbank, "Payments::Providers::Pagbank") unless Demo.enabled?
end
