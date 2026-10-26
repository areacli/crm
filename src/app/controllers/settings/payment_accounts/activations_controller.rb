# Ativa e desativa a conta de pagamento (12, R260). Só uma conta ativa por credor, modalidade e ambiente: ativar outra enquanto há uma ativa é recusado.
module Settings
  module PaymentAccounts
    class ActivationsController < ApplicationController
      before_action :set_account

      def create
        Payments::AccountManager.new(Current.user).activate(@account)
        panel_finish(edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), atualizar: true)
      rescue ActiveRecord::RecordInvalid => error
        panel_refuse(edit_settings_payment_account_path(@account), error.record.errors.full_messages.to_sentence)
      end

      def destroy
        Payments::AccountManager.new(Current.user).deactivate(@account)
        panel_finish(edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), atualizar: true)
      end

      private
        def set_account
          @account = PaymentAccount.find(params[:payment_account_id])
          authorize @account, :update?
        end
    end
  end
end
