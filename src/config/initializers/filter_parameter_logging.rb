# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Instrumentos de pagamento (12): certificado do fornecedor e credenciais das contas de pagamento
  :p12, :client_id, :client_secret,
  # Cartão (12, parte C, R278): o servidor nunca recebe dado de cartão; se um cliente com defeito mandar, não vai para o log. O `payment_token` já cai em `:token`.
  /\A(card_?)?(number|num)\z/i, /(\A|_)card(_|\z)/i, /holder/i, /expir/i, /\Apan\z/i
]
