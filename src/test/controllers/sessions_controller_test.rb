require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "a tela de entrada é pública" do
    get new_session_url

    assert_response :success
    assert_select "form[action='#{session_path}'] input[type=email][autocomplete=username]"
    assert_select "input[type=password][autocomplete=current-password]"
  end

  test "quem não tem sessão vai para a entrada e volta ao endereço pedido depois" do
    get root_url
    assert_redirected_to new_session_url

    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    assert_redirected_to root_url
  end

  test "entra com e-mail e senha certos, registra o acesso e a sessão vale" do
    assert_difference -> { AccessEvent.where(event: "login").count } => 1, -> { Session.count } => 1 do
      post session_url, params: { email_address: " JOANA@exemplo.com.br ", password: "senha-de-teste-1" }
    end
    assert_redirected_to root_url
    assert_not_nil users(:joana).reload.last_login_at

    get root_url
    assert_response :success
  end

  test "usuário inexistente, senha errada, usuário desativado e sem vínculo recebem a mesma mensagem" do
    [ [ "ninguem@exemplo.com.br", "qualquer" ], [ users(:joana).email_address, "errada" ],
      [ users(:inativo).email_address, "senha-de-teste-1" ], [ users(:sem_vinculo).email_address, "senha-de-teste-1" ] ].each do |email, senha|
      post session_url, params: { email_address: email, password: senha }

      assert_redirected_to new_session_url
      assert_equal "E-mail ou senha incorretos.", flash[:alert]
    end
    assert_equal 4, AccessEvent.where(event: "login_refused").count
  end

  test "a sessão acaba 8 horas depois da entrada (R28)" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    get root_url
    assert_response :success

    travel 8.hours + 1.minute do
      get root_url
      assert_redirected_to new_session_url
    end
    assert_equal 0, Session.count
  end

  test "a sessão cai quando o usuário é desativado (R30)" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    users(:joana).update!(active: false)

    get root_url
    assert_redirected_to new_session_url
  end

  test "sair encerra a sessão e registra" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }

    assert_difference -> { Session.count } => -1 do
      delete session_url
    end
    assert_redirected_to new_session_url
    assert_equal 1, AccessEvent.where(event: "logout").count
  end
end
