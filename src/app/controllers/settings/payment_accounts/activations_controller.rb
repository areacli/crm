# Ativa e desativa a conta de pagamento (12, R260). Só uma conta ativa por credor, modalidade e ambiente: ativar outra enquanto há uma ativa é recusado.
module Settings
  module PaymentAccounts
    class ActivationsController < ApplicationController
      before_action :set_account

      def create
        Payments::AccountManager.new(Current.user).activate(@account)
        redirect_to edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), status: :see_other
      rescue ActiveRecord::RecordInvalid => error
        redirect_to edit_settings_payment_account_path(@account), alert: error.record.errors.full_messages.to_sentence, status: :see_other
      end

      def destroy
        Payments::AccountManager.new(Current.user).deactivate(@account)
        redirect_to edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), status: :see_other
      end

      private
        def set_account
          @account = PaymentAccount.find(params[:payment_account_id])
          authorize @account, :update?
        end
    end
  end
end
