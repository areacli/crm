require "test_helper"

# Regra de senha (R26) e senha temporária/troca da própria senha (R37, R38, R39).
class Access::PasswordRulesTest < ActiveSupport::TestCase
  def user_with(password) = User.new(name: "Joana", email_address: "joana.souza@credor.example", password: password)

  test "R26: aceita 'cobranca-sem-pressa' e recusa as senhas fracas com o motivo" do
    assert user_with("cobranca-sem-pressa").valid?

    { "curta-demai" => "no mínimo 12", "123456789012" => "só números", "password1234" => "muito comum", "joana.souza1" => "parecida com o usuário",
      "xxJOANA.souza-xx" => "parecida com o usuário" }.each do |password, reason|
      user = user_with(password)

      assert_not user.valid?, "#{password} devia ser recusada"
      assert_match(/#{reason}/, user.errors[:password].join, password)
    end
  end

  test "R26: não pede maiúscula, número ou símbolo" do
    assert user_with("somente minusculas e espacos").valid?
  end

  test "R26: começo de e-mail com menos de 4 letras não conta como parecido" do
    assert User.new(name: "Ana", email_address: "ana@credor.example", password: "banana-ana-banana").valid?
  end

  test "R39: troca a senha informando a atual; a nova é gravada e a temporária some" do
    joana = users(:joana)
    joana.update!(temporary_password_until: 1.day.from_now)

    assert joana.change_password("outra-senha-longa-9", "outra-senha-longa-9", current: "senha-de-teste-1")

    assert_equal joana, User.authenticate_by(email_address: joana.email_address, password: "outra-senha-longa-9")
    assert_not joana.reload.temporary_password?
  end

  test "R39: senha atual errada, confirmação diferente, fraca ou igual à atual são recusadas" do
    joana = users(:joana)

    assert_not joana.change_password("outra-senha-longa-9", "outra-senha-longa-9", current: "errada")
    assert joana.errors[:current_password].any?

    assert_not joana.change_password("outra-senha-longa-9", "diferente-diferente", current: "senha-de-teste-1")
    assert joana.errors[:password_confirmation].any?

    assert_not joana.change_password("123456789012", "123456789012", current: "senha-de-teste-1")
    assert_not joana.change_password("senha-de-teste-1", "senha-de-teste-1", current: "senha-de-teste-1")
    assert_includes joana.errors[:password], "não pode ser igual à senha atual"

    assert_not joana.change_password("", "", current: "senha-de-teste-1")
    assert_equal joana, User.authenticate_by(email_address: joana.email_address, password: "senha-de-teste-1")
  end

  test "R38: no primeiro acesso a senha atual não é pedida, mas a nova não pode ser igual à temporária" do
    marta = users(:marta)
    temporary = Access::TemporaryPassword.generate
    marta.update!(password: temporary, temporary_password_until: 1.day.from_now)

    assert_not marta.change_password(temporary, temporary, require_current: false)
    assert_includes marta.errors[:password], "não pode ser igual à senha atual"
    assert marta.change_password("definitiva-bem-longa-1", "definitiva-bem-longa-1", require_current: false)
    assert_not marta.reload.temporary_password?
  end

  test "R37: a senha temporária vence em 72 horas e o usuário deixa de poder entrar" do
    marta = users(:marta)
    marta.update!(temporary_password_until: 72.hours.from_now)
    assert marta.can_sign_in?

    travel 72.hours + 1.minute do
      assert marta.temporary_password_expired?
      assert_not marta.can_sign_in?
    end
  end

  test "R27: a quinta tentativa errada bloqueia por 15 minutos e zera a contagem; um login certo também zera" do
    joana = users(:joana)

    4.times { assert_not joana.register_failed_login! }
    assert_equal 4, joana.reload.failed_attempts
    joana.register_successful_login!
    assert_equal 0, joana.reload.failed_attempts

    4.times { joana.register_failed_login! }
    assert joana.register_failed_login!
    assert joana.reload.locked?
    assert_equal 0, joana.failed_attempts
    travel(15.minutes + 1.second) { assert_not joana.locked? }
  end
end
