module Payments
  module Providers
    class Bradesco
      # Autenticação da API de cobrança do Bradesco (12, revisão 4, R284j). O manual de cobrança 1.6.4 não tem uma linha sobre ela (bloqueio B1 do
      # plano): nem token, nem assinatura, nem certificado. A única pista é o erro `CBTT0930 TIMESTAMP DA SOLICITAÇÃO INVÁLIDO` (C l. 2305). Por isso a
      # autenticação é uma peça trocável, com a interface `configured?`, `headers(account, method:, path:, body:)` e `tls(account)`: quando o documento do
      # banco chegar, a peça de verdade entra aqui e o resto do adaptador não muda. Até lá, `Unconfigured` recusa toda chamada antes de sair qualquer
      # dado, e o boleto do Bradesco não aparece no cadastro de integrações.
      module BoletoAuth
        class Unconfigured
          def configured? = false

          def headers(_account, **) = raise(Error, I18n.t("payments.providers.bradesco.errors.boleto_auth_missing"))

          def tls(_account) = raise(Error, I18n.t("payments.providers.bradesco.errors.boleto_auth_missing"))
        end
      end
    end
  end
end
