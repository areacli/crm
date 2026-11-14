module Payments
  # Endereço do webhook de uma conta de pagamento (12, parte D, R281): `/webhooks/pagamentos/contas/:conta?hmac=...`. O `hmac` é derivado do segredo
  # do webhook da conta (nunca o segredo em si, que não deve ir a log de proxy nem ao fornecedor) e vale enquanto o segredo vale (vigência dupla de 24 horas,
  # R265). Sem endereço público configurado (`CRM_PUBLIC_URL`) não há URL, e o fornecedor não é avisado de onde chamar.
  module WebhookUrl
    module_function

    def base = Rails.configuration.x.payments.public_url.to_s.chomp("/").presence

    # Endereço completo para o fornecedor chamar (com o `hmac`), ou nil sem endereço público ou sem segredo gerado.
    def for(account)
      secret = account.secrets["webhook_secret"].presence
      return unless base && secret

      "#{base}/webhooks/pagamentos/contas/#{account.id}?hmac=#{token(account, secret)}"
    end

    # Caracteres do `hmac` na URL (12, revisão 4, R284g): o HMAC-SHA256 truncado em 128 bits, para a URL caber nos 100 caracteres que o cadastro de
    # webhook do boleto do Bradesco aceita.
    LENGTH = 32
    MAX_URL = 100

    # O valor do `hmac` da URL: HMAC-SHA256 do segredo sobre a conta, nos primeiros 32 caracteres hexadecimais.
    def token(account, secret) = full_token(account, secret)[0, LENGTH]

    # O HMAC inteiro (64), o que as URLs cadastradas antes da revisão 4 levam.
    def full_token(account, secret) = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "webhook-url:#{account.id}")

    # O `hmac` recebido vale se bate com o segredo atual ou, durante a vigência dupla, com o anterior (comparação em tempo constante). Vale o de 32 e
    # o de 64: as integrações já cadastradas não precisam ser refeitas.
    def valid?(account, received)
      received = received.to_s
      account.webhook_secrets.any? do |secret|
        full = full_token(account, secret)
        expected = received.bytesize == full.bytesize ? full : full[0, LENGTH]
        received.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.fixed_length_secure_compare(received, expected)
      end
    end
  end
end
