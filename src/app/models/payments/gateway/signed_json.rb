module Payments
  module Gateway
    # Adaptador genérico: o corpo é JSON e o cabeçalho `X-Signature` traz o HMAC SHA-256 do corpo, em hexadecimal (com ou sem o prefixo
    # `sha256=`), feito com o segredo do canal. Formato do corpo:
    #
    #   { "id": "evt_1", "type": "payment.received",
    #     "data": { "identifier": "E123", "document": "52998224725", "bill_number": "NF-1", "paid_on": "2026-10-18",
    #               "amount_cents": 40000, "method": "pix", "system": "SAP", "external_bill_id": "T-77" } }
    #
    # `system` é o nome do sistema do credor de onde o pagamento vem (17, R417c): obrigatório quando o credor tem mais de um sistema além do CRM, menos
    # no pagamento com número de promessa ou de acordo. `external_bill_id`, opcional, é o id do título nesse sistema, quando ele tem id próprio.
    class SignedJson
      SIGNATURE_HEADER = "X-Signature".freeze
      PAYMENT_TYPE = "payment.received".freeze

      def verify!(body:, headers:, secret:)
        given = headers[SIGNATURE_HEADER].to_s.delete_prefix("sha256=")
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, body.to_s)
        # Comparação em tempo constante: a resposta não revela quantos caracteres da assinatura estavam certos.
        raise InvalidSignature, "assinatura inválida" unless given.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.fixed_length_secure_compare(given, expected)
      end

      def event(payload)
        raise InvalidPayload, "corpo fora do formato" unless payload.is_a?(Hash)

        id = payload["id"].to_s.strip
        raise InvalidPayload, "identificador do evento ausente" if id.empty? || id.length > 200

        kind = payload["type"].to_s
        return Event.new(id: id, kind: kind, payment: nil) unless kind == PAYMENT_TYPE

        data = payload["data"]
        raise InvalidPayload, "dados do pagamento ausentes" unless data.is_a?(Hash)

        Event.new(id: id, kind: kind, payment: {
          identifier: data["identifier"].to_s, document: data["document"].to_s, bill_number: data["bill_number"].to_s,
          paid_on: data["paid_on"].to_s, amount_cents: data["amount_cents"], payment_method: data["method"].to_s,
          system: data["system"].to_s, external_bill_id: data["external_bill_id"].to_s.presence
        })
      end
    end
  end
end
