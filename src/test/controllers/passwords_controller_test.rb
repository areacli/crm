require "test_helper"

# Trocar a própria senha (R39) e definir a senha no primeiro acesso (R38), pela SPA (decisão 0025): JSON, erros por campo com 422.
class PasswordsControllerTest < ActionDispatch::IntegrationTest
  def trocar(atributos) = patch(password_url, params: { password: atributos }, as: :json)

  test "R39: troca a senha informando a atual; as outras sessões caem e a atual continua" do
    joana = users(:joana)
    outra = joana.sessions.create!(user_agent: "celular")
    post session_url, params: { email_address: joana.email_address, password: "senha-de-teste-1" }, as: :json

    trocar current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa"

    assert_response :success
    assert_equal "Senha alterada. As outras sessões abertas foram encerradas.", response.parsed_body["mensagem"]
    assert_not Session.exists?(outra.id)
    get menu_url(format: :json)
    assert_response :success
    assert_equal joana, User.authenticate_by(email_address: joana.email_address, password: "uma-senha-nova-bem-longa")
    event = AccessEvent.find_by!(event: "password_changed", user: joana)
    assert_not_includes event.details.to_json, "uma-senha-nova"
  end

  test "R39: senha atual errada, fraca ou confirmação diferente não trocam nada e dizem o campo" do
    sign_in_as users(:joana)

    { "current_password" => { current_password: "errada", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa" },
      "password" => { current_password: "senha-de-teste-1", password: "123456789012", password_confirmation: "123456789012" },
      "password_confirmation" => { current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "outra-coisa-diferente" } }.each do |campo, attributes|
      trocar attributes

      assert_response :unprocessable_content
      assert response.parsed_body.dig("erros", campo).present?, campo
    end
    assert User.authenticate_by(email_address: "joana@exemplo.com.br", password: "senha-de-teste-1")
  end

  test "R38: o primeiro acesso define a senha sem repetir a temporária; 123456789012 e a própria temporária são recusadas" do
    temporary = Access::TemporaryPassword.generate
    users(:carlos).update!(password: temporary, temporary_password_until: 72.hours.from_now)
    post session_url, params: { email_address: users(:carlos).email_address, password: temporary }, as: :json
    assert response.parsed_body.dig("usuario", "senha_temporaria")

    trocar password: temporary, password_confirmation: temporary
    assert_response :unprocessable_content
    assert_match(/igual à senha atual/, response.parsed_body["mensagem"])

    trocar password: "123456789012", password_confirmation: "123456789012"
    assert_response :unprocessable_content
    assert_match(/só números/, response.parsed_body["mensagem"])

    trocar password: "minha-senha-definitiva", password_confirmation: "minha-senha-definitiva"
    assert_response :success
    get menu_url(format: :json)
    assert_response :success
    assert_not users(:carlos).reload.temporary_password?
  end

  test "o endereço antigo da tela de senha leva à SPA; sem sessão, à entrada" do
    get edit_password_url
    assert_redirected_to root_url

    sign_in_as users(:joana)
    get edit_password_url
    assert_redirected_to "#{root_path}#/senha"
  end
end
