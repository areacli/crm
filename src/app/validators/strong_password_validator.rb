# Regra de senha (R26): mínimo de 12 caracteres; recusa senha só numérica, comum ou parecida com o usuário. Sem exigência de
# maiúscula, número ou símbolo, nem troca periódica. `similar_to:` diz de onde tirar a identidade (padrão: o e-mail do registro).
class StrongPasswordValidator < ActiveModel::EachValidator
  MIN_LENGTH = 12

  # Senhas comuns de 12 caracteres ou mais, que passariam pelo tamanho mínimo.
  COMMON = %w[
    password1234 password12345 password123456 qwertyuiop12 qwerty123456 qwertyuiopas abcdefghijkl abcd12345678 abc123456789
    senha1234567 senha12345678 mudar1234567 mudar@123456 brasil123456 iloveyou1234 letmein12345 welcome12345 administrator
    admin1234567 admin@123456 changeme1234 123456789abc 1q2w3e4r5t6y 1qaz2wsx3edc asdfghjkl123 zxcvbnm12345
  ].freeze

  # Começo de e-mail muito curto ("ana") aparece em muitas senhas sem ter relação com o usuário: só vale comparar a partir de 4.
  MIN_IDENTITY_LENGTH = 4

  def validate_each(record, attribute, value)
    password = value.to_s
    if password.length < MIN_LENGTH then record.errors.add(attribute, :password_too_short, count: MIN_LENGTH)
    elsif password.match?(/\A\d+\z/) then record.errors.add(attribute, :password_only_digits)
    elsif COMMON.include?(password.downcase) then record.errors.add(attribute, :password_common)
    elsif similar_to_identity?(record, password) then record.errors.add(attribute, :password_like_user)
    end
  end

  private
    def similar_to_identity?(record, password)
      identity = record.public_send(options.fetch(:similar_to, :email_address)).to_s.split("@").first.to_s.downcase
      return false if identity.length < MIN_IDENTITY_LENGTH

      typed = password.downcase
      typed.include?(identity) || identical_but_for_two?(typed, identity)
    end

    # Quase igual ao usuário (um ou dois caracteres de diferença): distância de edição de no máximo 2.
    def identical_but_for_two?(typed, identity)
      return false if (typed.length - identity.length).abs > 2

      previous = (0..identity.length).to_a
      typed.each_char.with_index(1) do |letter, row|
        current = [ row ]
        identity.each_char.with_index(1) do |other, column|
          current << [ previous[column] + 1, current[column - 1] + 1, previous[column - 1] + (letter == other ? 0 : 1) ].min
        end
        previous = current
      end
      previous.last <= 2
    end
end
