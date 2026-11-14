# A volta da autorização no fornecedor (12, revisão 5, R284k), numa rota fixa (o endereço de volta é cadastrado na aplicação da instalação no fornecedor):
# confere o `state` de uso único da sessão de quem começou, a permissão 14 no credor da integração, troca o código pelos tokens e leva à integração na
# casca, com o resultado em palavras. A troca é uma chamada curta ao fornecedor, feita aqui mesmo: o navegador mostra a espera da página até ela terminar.
module Settings
  module PaymentAccounts
    class ConnectionReturnsController < ApplicationController
      skip_before_action :redirect_page_to_shell

      def show
        connection = Payments::Connection.new(Current.user)
        account_id = session[Payments::Connection::SESSION_KEY]&.then { |stored| stored["account_id"] || stored[:account_id] }
        account = connection.finish(session, state: params[:state], code: params[:code], error: params[:error]) { |found| authorize found, :update? }
        redirect_to "/#/configuracao/integracoes/#{account.id}/editar", flash: { connection_notice: t("payments.connection.done", nickname: account.nickname) }, status: :see_other
      rescue Payments::Connection::Refused => error
        destino = account_id ? "/#/configuracao/integracoes/#{account_id}/editar" : "/"
        redirect_to destino, flash: { connection_alert: t("payments.connection.failed", detail: error.message) }, status: :see_other
      end
    end
  end
end
