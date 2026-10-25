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

  test "R27: cinco senhas erradas bloqueiam por 15 minutos, nem a senha certa entra, e a mensagem é a mesma" do
    5.times do
      post session_url, params: { email_address: users(:joana).email_address, password: "errada" }
      assert_equal "E-mail ou senha incorretos.", flash[:alert]
    end
    assert users(:joana).reload.locked?
    assert_equal 1, AccessEvent.where(event: "account_locked", user: users(:joana)).count

    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    assert_redirected_to new_session_url
    assert_equal "E-mail ou senha incorretos.", flash[:alert]
    assert_equal 1, AccessEvent.where(event: "login_locked", user: users(:joana)).count

    travel 15.minutes + 1.second do
      post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
      assert_redirected_to root_url
    end
  end

  test "R27: um login certo zera a contagem de erros" do
    4.times { post session_url, params: { email_address: users(:joana).email_address, password: "errada" } }
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    delete session_url
    4.times { post session_url, params: { email_address: users(:joana).email_address, password: "errada" } }

    assert_not users(:joana).reload.locked?
  end

  test "R37: a senha temporária de 73 horas é recusada com a mensagem de sempre; a redefinição a devolve" do
    password = Access::TemporaryPassword.generate
    users(:carlos).update!(password: password, temporary_password_until: 72.hours.from_now)

    travel 73.hours do
      post session_url, params: { email_address: users(:carlos).email_address, password: password }
      assert_redirected_to new_session_url
      assert_equal "E-mail ou senha incorretos.", flash[:alert]
    end

    nova = Access::UserManager.new(users(:joana)).reset_password(memberships(:carlos_alfa))
    post session_url, params: { email_address: users(:carlos).email_address, password: nova }
    assert_redirected_to root_url
  end

  test "R38: com senha temporária só a tela de definir a senha abre; sair continua possível" do
    users(:carlos).update!(temporary_password_until: 72.hours.from_now)
    sign_in_as users(:carlos)

    %w[/ /clientes /importacoes /usuarios /perfis /avisos].each do |path|
      get path
      assert_redirected_to edit_password_url, path
    end
    get edit_password_url
    assert_response :success
    assert_select "h1", "Defina sua senha"
    assert_select "nav[aria-label=Menu]", count: 0
    assert_select "#sino", count: 0

    delete session_url
    assert_redirected_to new_session_url
  end

  test "o e-mail digitado em outra grafia entra (R36)" do
    post session_url, params: { email_address: "  JOANA@EXEMPLO.COM.BR ", password: "senha-de-teste-1" }

    assert_redirected_to root_url
  end

  test "a sessão acaba depois de 30 minutos sem atividade (R28)" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    travel 31.minutes do
      get root_url
      assert_redirected_to new_session_url
    end
    assert_equal 0, Session.count
  end

  test "a atividade renova os 30 minutos, mas as 8 horas continuam sendo o teto (R28)" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    start = Time.current
    (1..16).each do |step|
      travel_to start + (step * 29).minutes do
        get root_url
        assert_response :success, "passo #{step}"
      end
    end
    travel_to start + 8.hours + 10.minutes do
      get root_url
      assert_redirected_to new_session_url
    end
  end

  test "a conexão do WebSocket também recusa a sessão parada por 30 minutos (R28)" do
    post session_url, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    session = Session.sole
    assert_not session.expired?
    travel 31.minutes do
      assert_predicate session.reload, :expired?
    end
  end
end
