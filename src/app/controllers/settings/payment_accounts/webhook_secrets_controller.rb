# Gera (ou troca) o segredo do nosso webhook da conta (12, R265). Aparece uma única vez, na tela de edição; o anterior vale por mais 24 horas.
module Settings
  module PaymentAccounts
    class WebhookSecretsController < ApplicationController
      def create
        account = PaymentAccount.find(params[:payment_account_id])
        authorize account, :update?
        flash[:webhook_secret] = Payments::AccountManager.new(Current.user).regenerate_webhook_secret(account)
        panel_finish(edit_settings_payment_account_path(account), notice: "Segredo gerado. Copie-o agora: ele não aparece de novo.", navegar: true)
      end
    end
  end
end
