module Payments
  module Providers
    # O aviso não vem de quem diz ser (assinatura, HMAC na URL, IP ou certificado do cliente): a rota responde 401 e nada é gravado.
    class InvalidSignature < Error; end
  end
end
