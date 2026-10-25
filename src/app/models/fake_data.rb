# Dados fictícios para a demonstração e as medições: CPF e CNPJ válidos que não pertencem a ninguém conhecido.
module FakeData
  FIRST_NAMES = %w[Maria João Ana Pedro Lucas Juliana Carlos Fernanda Rafael Patrícia Bruno Camila].freeze
  LAST_NAMES = %w[Silva Souza Oliveira Santos Pereira Lima Costa Ribeiro Almeida Carvalho Gomes Martins].freeze

  module_function

  def cpf(seed)
    digits = (100_000_000 + (seed * 7919) % 899_999_999).to_s.rjust(9, "0").chars.map(&:to_i)
    digits[8] = (digits[8] + 1) % 10 if digits.uniq.size == 1
    [ 10, 11 ].each do |length|
      sum = digits.each_with_index.sum { |digit, index| digit * (length - index) }
      digits << ((sum * 10) % 11 % 10)
    end
    digits.join
  end

  def name(seed)
    "#{FIRST_NAMES[seed % 12]} #{LAST_NAMES[(seed / 12) % 12]} #{LAST_NAMES[(seed / 144) % 12]} #{seed / 1728}"
  end
end
