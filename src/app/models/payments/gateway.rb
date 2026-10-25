module Payments
  # Contrato entre o CRM e o provedor de pagamento, sem depender de nenhum provedor. Cada adaptador responde a duas perguntas:
  #
  #   verify!(body:, headers:, secret:)  levanta InvalidSignature se o corpo não vem de quem tem o segredo do canal;
  #   event(payload)                      devolve um Event (a partir do JSON já lido) ou levanta InvalidPayload.
  #
  # O CRM traz o adaptador `signed_json` (HMAC SHA-256 do corpo em `X-Signature`). Um provedor real entra como um adaptador novo, aqui
  # registrado, sem mexer no resto: o endereço, a idempotência pelo identificador do evento, a fila e a baixa são os mesmos.
  module Gateway
    class InvalidSignature < StandardError; end
    class InvalidPayload < StandardError; end

    # id: identificador do evento no provedor (a chave da idempotência); payment: dados do pagamento, ou nil quando o evento não é de
    # pagamento recebido (é guardado e ignorado). Os dados: identifier, document, bill_number, paid_on (Date), amount_cents, payment_method.
    Event = Data.define(:id, :kind, :payment)

    ADAPTERS = { "signed_json" => "Payments::Gateway::SignedJson" }.freeze

    module_function

    def names = ADAPTERS.keys

    def for(name) = ADAPTERS.fetch(name).constantize.new
  end
end
