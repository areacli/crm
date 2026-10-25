module Access
  # Senha temporária (R37): quatro grupos de quatro caracteres, sem os que se confundem (0/O, 1/l/I), válida por 72 horas.
  # Gerada com o gerador aleatório seguro do sistema; o banco guarda só o hash.
  module TemporaryPassword
    VALID_FOR = 72.hours
    ALPHABET = ("a".."z").to_a + ("A".."Z").to_a + ("2".."9").to_a - %w[l I O o]

    def self.generate = Array.new(4) { Array.new(4) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join }.join("-")

    def self.expires_at = VALID_FOR.from_now
  end
end
