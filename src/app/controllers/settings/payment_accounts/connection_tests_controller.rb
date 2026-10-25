# "Testar conexão" da conta (12, R266): chama o teste do adaptador e grava o resultado na conta e no histórico.
module Settings
  module PaymentAccounts
    class ConnectionTestsController < ApplicationController
      def create
        account = PaymentAccount.find(params[:payment_account_id])
        authorize account, :test?
        result = Payments::AccountManager.new(Current.user).test_connection(account)
        message = t(".done", nickname: account.nickname, message: result.message)
        flash_type = result.ok == false ? :alert : :notice
        redirect_to edit_settings_payment_account_path(account), flash_type => message, status: :see_other
      end
    end
  end
end
