require "test_helper"

# Trocar a própria senha (R39) e definir a senha no primeiro acesso (R38).
class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "R39: troca a senha informando a atual; as outras sessões caem e a atual continua" do
    joana = users(:joana)
    outra = joana.sessions.create!(user_agent: "celular")
    post session_url, params: { email_address: joana.email_address, password: "senha-de-teste-1" }

    patch password_url, params: { password: { current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa" } }

    assert_redirected_to root_url
    assert_not Session.exists?(outra.id)
    get root_url
    assert_response :success
    assert_equal joana, User.authenticate_by(email_address: joana.email_address, password: "uma-senha-nova-bem-longa")
    event = AccessEvent.find_by!(event: "password_changed", user: joana)
    assert_not_includes event.details.to_json, "uma-senha-nova"
  end

  test "R39: senha atual errada, fraca ou confirmação diferente não trocam nada" do
    sign_in_as users(:joana)

    [ { current_password: "errada", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa" },
      { current_password: "senha-de-teste-1", password: "123456789012", password_confirmation: "123456789012" },
      { current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "outra-coisa-diferente" } ].each do |attributes|
      patch password_url, params: { password: attributes }

      assert_response :unprocessable_content
      assert_select "[role=alert]"
    end
    assert User.authenticate_by(email_address: "joana@exemplo.com.br", password: "senha-de-teste-1")
  end

  test "R38: o primeiro acesso define a senha sem repetir a temporária; 123456789012 e a própria temporária são recusadas" do
    temporary = Access::TemporaryPassword.generate
    users(:carlos).update!(password: temporary, temporary_password_until: 72.hours.from_now)
    post session_url, params: { email_address: users(:carlos).email_address, password: temporary }
    assert_redirected_to root_url
    follow_redirect!
    assert_redirected_to edit_password_url

    patch password_url, params: { password: { password: temporary, password_confirmation: temporary } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /igual à senha atual/

    patch password_url, params: { password: { password: "123456789012", password_confirmation: "123456789012" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /só números/

    patch password_url, params: { password: { password: "minha-senha-definitiva", password_confirmation: "minha-senha-definitiva" } }
    assert_redirected_to root_url
    get root_url
    assert_response :success
    assert_not users(:carlos).reload.temporary_password?
  end

  test "sem sessão a tela de senha pede o login" do
    get edit_password_url

    assert_redirected_to new_session_url
  end
end
