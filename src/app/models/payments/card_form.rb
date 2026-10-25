module Payments
  # O que a página de pagamento precisa para o cartão (12, R278): o módulo do navegador e a biblioteca do fornecedor (que o adaptador declara), os valores
  # públicos da conta e as opções de parcelamento do adaptador (limitadas ao máximo da conta). Nada específico de fornecedor fica fora do adaptador.
  CardForm = Data.define(:driver, :script, :config, :options) do
    # nil quando o link não oferece cartão ou a conta de cartão deixou de servir.
    def self.for(checkout, brand: nil)
      return unless checkout.offers?("card")

      account = Checkouts.card_account(checkout.tenant, checkout.environment)
      return unless account&.provider_available?

      declared = account.manifest.capabilities.fetch(:card_checkout)
      new(driver: declared.fetch(:driver), script: declared[:script], config: account.adapter.card_checkout_config(account), options: options_for(account, checkout, brand))
    end

    def self.options_for(account, checkout, brand)
      limit = account.config.fetch("max_installments", 1).to_i
      options = account.adapter.installments(account, amount_cents: checkout.amount_cents, brand: brand).select { |option| option.installments <= limit }
      options.presence || [ Providers::InstallmentOption.new(installments: 1, installment_cents: checkout.amount_cents, total_cents: checkout.amount_cents, has_interest: false) ]
    rescue Providers::Error
      [ Providers::InstallmentOption.new(installments: 1, installment_cents: checkout.amount_cents, total_cents: checkout.amount_cents, has_interest: false) ]
    end
  end
end
