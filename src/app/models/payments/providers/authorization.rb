module Payments
  module Providers
    # Contrato da conexão por autorização (12, revisão 5, R284k e R284l): o fornecedor cujo manifesto declara `credentials: "authorization"` não tem
    # campos de credencial; o gestor do credor autoriza o CRM numa página do fornecedor (nunca o cliente que paga) e o CRM guarda os tokens, que giram a
    # cada renovação. O adaptador só traduz: monta o endereço da autorização e troca o código ou o token de renovação por tokens novos. Quem guarda,
    # trava e renova é `Payments::Connection`, a mesma peça para qualquer fornecedor (e, na decisão 0033, para o módulo comum de adaptadores).
    #
    # `app`: a aplicação da instalação no fornecedor, por ambiente (`client_id`, `client_secret` e, se o fornecedor pedir, o token da conta da plataforma),
    # que vem da configuração de operação e nunca da tela.
    module Authorization
      # Tokens normalizados. `expires_at`: quando o de acesso vence (nil = o fornecedor não disse). `account_label`: o que identifica a conta
      # autorizada para mostrar ao gestor (nunca segredo).
      Tokens = Data.define(:access_token, :refresh_token, :expires_at, :account_label) do
        def initialize(access_token:, refresh_token: nil, expires_at: nil, account_label: nil) = super
      end

      def authorization_url(account, app:, state:, redirect_uri:) = not_implemented(:authorization, __method__)

      def exchange_authorization_code(account, app:, code:, redirect_uri:) = not_implemented(:authorization, __method__)

      def refresh_authorization(account, app:, refresh_token:) = not_implemented(:authorization, __method__)
    end

    # O fornecedor recusou a renovação (ou o código): a integração fica desconectada até o gestor autorizar de novo.
    class AuthorizationRefused < Error; end
  end
end
