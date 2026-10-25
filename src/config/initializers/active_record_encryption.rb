# Cifragem de atributos do Active Record (guia de Active Record Encryption): as chaves saem do `secret_key_base`, que já é segredo do
# ambiente (variável `SECRET_KEY_BASE` em produção), sem um segundo segredo para guardar. Hoje cifra só o segredo do webhook de
# pagamento de cada canal (HMAC precisa do valor em claro, então o hash não serve).
Rails.application.config.after_initialize do
  generator = Rails.application.key_generator
  ActiveRecord::Encryption.configure(
    primary_key: generator.generate_key("active_record_encryption.primary_key", 32).unpack1("H*"),
    deterministic_key: generator.generate_key("active_record_encryption.deterministic_key", 32).unpack1("H*"),
    key_derivation_salt: generator.generate_key("active_record_encryption.key_derivation_salt", 32).unpack1("H*")
  )
end
