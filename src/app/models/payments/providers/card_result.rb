module Payments
  module Providers
    # Resultado de uma cobrança de cartão (vocabulário nosso). `status`: `approved` (o emissor aprovou; o crédito ainda não foi confirmado, o que vem
    # pelo aviso do fornecedor), `paid` (já confirmado) ou `declined` (recusado). Na recusa, `refusal_code` classifica o motivo
    # (`invalid_data`, `security`, `try_later` ou `other`) e `retry` diz se tentar de novo pode dar certo; `refusal_reason` é o texto do fornecedor,
    # que vai só para o registro (a tela do cliente mostra a nossa mensagem, em pt-BR, pelo código). Nada aqui é dado de cartão.
    CardResult = Data.define(:external_id, :status, :amount_cents, :installments, :refusal_code, :retry, :refusal_reason) do
      def initialize(external_id: nil, status:, amount_cents: nil, installments: 1, refusal_code: nil, retry: false, refusal_reason: nil)
        super
      end

      def declined? = status == "declined"
    end
  end
end
