# Conexão por autorização da integração (12, revisão 5, R284k): "Conectar ao <fornecedor>" leva o gestor (nunca o cliente que paga) à página de
# autorização do fornecedor; "Desconectar" tira os tokens. A permissão 14 vale no credor da integração. "Conectar" é uma navegação da janela inteira (o
# link sai da casca com `target="_top"`), por isso pula o filtro que manda páginas para a casca.
module Settings
  module PaymentAccounts
    class ConnectionsController < ApplicationController
      skip_before_action :redirect_page_to_shell, only: :new
      before_action :set_account

      def new
        redirect_to Payments::Connection.new(Current.user).start(@account, session), allow_other_host: true, status: :see_other
      rescue Payments::Connection::Refused => error
        redirect_to "/#/configuracao/integracoes/#{@account.id}/editar", flash: { connection_alert: error.message }, status: :see_other
      end

      def destroy
        Payments::Connection.new(Current.user).disconnect(@account)
        panel_finish(edit_settings_payment_account_path(@account), notice: t("payments.connection.disconnected_done", nickname: @account.nickname), atualizar: true)
      end

      private
        def set_account
          @account = PaymentAccount.find(params[:payment_account_id])
          authorize @account, :update?
        end
    end
  end
end
