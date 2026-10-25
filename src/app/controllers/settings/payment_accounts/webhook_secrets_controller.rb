# Gera (ou troca) o segredo do nosso webhook da conta (12, R265). Aparece uma única vez, na tela de edição; o anterior vale por mais 24 horas.
module Settings
  module PaymentAccounts
    class WebhookSecretsController < ApplicationController
      def create
        account = PaymentAccount.find(params[:payment_account_id])
        authorize account, :update?
        flash[:webhook_secret] = Payments::AccountManager.new(Current.user).regenerate_webhook_secret(account)
        redirect_to edit_settings_payment_account_path(account), status: :see_other
      end
    end
  end
end
