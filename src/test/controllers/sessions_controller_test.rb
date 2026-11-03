require "test_helper"

# Entrada e saída pela SPA (02; decisão 0025): o formulário da casca manda JSON e recebe o usuário, ou a mensagem com 422.
class SessionsControllerTest < ActionDispatch::IntegrationTest
  def entrar(email, senha) = post(session_url, params: { email_address: email, password: senha }, as: :json)
  def mensagem = response.parsed_body["mensagem"]

  test "o endereço antigo da entrada leva à casca" do
    get new_session_url
    assert_redirected_to root_url
  end

  test "quem não tem sessão: página do servidor vai à casca e volta ao endereço pedido depois; pedido de dados recebe 401" do
    get customers_url
    assert_redirected_to root_url
    get menu_url(format: :json)
    assert_response :unauthorized

    entrar users(:joana).email_address, "senha-de-teste-1"
    assert_response :created
    assert_equal customers_url, response.parsed_body["destino"]
  end

  test "entra com e-mail e senha certos, registra o acesso e a sessão vale" do
    assert_difference -> { AccessEvent.where(event: "login").count } => 1, -> { Session.count } => 1 do
      entrar " JOANA@exemplo.com.br ", "senha-de-teste-1"
    end
    assert_response :created
    assert_equal "/", response.parsed_body["destino"]
    assert_equal users(:joana).name, response.parsed_body.dig("usuario", "nome")
    assert_not_nil users(:joana).reload.last_login_at

    get menu_url(format: :json)
    assert_response :success
  end

  test "usuário inexistente, senha errada, usuário desativado e sem vínculo recebem a mesma mensagem" do
    [ [ "ninguem@exemplo.com.br", "qualquer" ], [ users(:joana).email_address, "errada" ],
      [ users(:inativo).email_address, "senha-de-teste-1" ], [ users(:sem_vinculo).email_address, "senha-de-teste-1" ] ].each do |email, senha|
      entrar email, senha

      assert_response :unprocessable_content
      assert_equal "E-mail ou senha incorretos.", mensagem
    end
    assert_equal 4, AccessEvent.where(event: "login_refused").count
  end

  test "a sessão acaba 8 horas depois da entrada (R28)" do
    entrar users(:joana).email_address, "senha-de-teste-1"
    get menu_url(format: :json)
    assert_response :success

    travel 8.hours + 1.minute do
      get menu_url(format: :json)
      assert_response :unauthorized
    end
    assert_equal 0, Session.count
  end

  test "a sessão cai quando o usuário é desativado (R30)" do
    entrar users(:joana).email_address, "senha-de-teste-1"
    users(:joana).update!(active: false)

    get menu_url(format: :json)
    assert_response :unauthorized
  end

  test "sair encerra a sessão e registra" do
    entrar users(:joana).email_address, "senha-de-teste-1"

    assert_difference -> { Session.count } => -1 do
      delete session_url, as: :json
    end
    assert_response :no_content
    assert_equal 1, AccessEvent.where(event: "logout").count
  end

  test "R27: cinco senhas erradas bloqueiam por 15 minutos, nem a senha certa entra, e a mensagem é a mesma" do
    5.times do
      entrar users(:joana).email_address, "errada"
      assert_equal "E-mail ou senha incorretos.", mensagem
    end
    assert users(:joana).reload.locked?
    assert_equal 1, AccessEvent.where(event: "account_locked", user: users(:joana)).count

    entrar users(:joana).email_address, "senha-de-teste-1"
    assert_response :unprocessable_content
    assert_equal "E-mail ou senha incorretos.", mensagem
    assert_equal 1, AccessEvent.where(event: "login_locked", user: users(:joana)).count

    travel 15.minutes + 1.second do
      entrar users(:joana).email_address, "senha-de-teste-1"
      assert_response :created
    end
  end

  test "R27: um login certo zera a contagem de erros" do
    4.times { entrar users(:joana).email_address, "errada" }
    entrar users(:joana).email_address, "senha-de-teste-1"
    delete session_url, as: :json
    4.times { entrar users(:joana).email_address, "errada" }

    assert_not users(:joana).reload.locked?
  end

  test "R37: a senha temporária de 73 horas é recusada com a mensagem de sempre; a redefinição a devolve" do
    password = Access::TemporaryPassword.generate
    users(:carlos).update!(password: password, temporary_password_until: 72.hours.from_now)

    travel 73.hours do
      entrar users(:carlos).email_address, password
      assert_response :unprocessable_content
      assert_equal "E-mail ou senha incorretos.", mensagem
    end

    nova = Access::UserManager.new(users(:joana)).reset_password(memberships(:carlos_alfa))
    entrar users(:carlos).email_address, nova
    assert_response :created
    assert response.parsed_body.dig("usuario", "senha_temporaria")
  end

  test "R38: com senha temporária a casca mostra a definição de senha; páginas levam à casca, dados são recusados; sair continua possível" do
    users(:carlos).update!(temporary_password_until: 72.hours.from_now)
    sign_in_as users(:carlos)

    %w[/clientes /importacoes /usuarios /perfis /avisos].each do |path|
      get path
      assert_redirected_to root_url, path
    end
    get menu_url(format: :json)
    assert_response :forbidden
    get root_url
    assert_response :success
    assert_select "#configuracao-da-casca", /"senha_temporaria":true/

    delete session_url, as: :json
    assert_response :no_content
  end

  test "o e-mail digitado em outra grafia entra (R36)" do
    entrar "  JOANA@EXEMPLO.COM.BR ", "senha-de-teste-1"

    assert_response :created
  end

  test "a sessão acaba depois de 30 minutos sem atividade (R28)" do
    entrar users(:joana).email_address, "senha-de-teste-1"
    travel 31.minutes do
      get menu_url(format: :json)
      assert_response :unauthorized
    end
    assert_equal 0, Session.count
  end

  test "a atividade renova os 30 minutos, mas as 8 horas continuam sendo o teto (R28)" do
    entrar users(:joana).email_address, "senha-de-teste-1"
    start = Time.current
    (1..16).each do |step|
      travel_to start + (step * 29).minutes do
        get menu_url(format: :json)
        assert_response :success, "passo #{step}"
      end
    end
    travel_to start + 8.hours + 10.minutes do
      get menu_url(format: :json)
      assert_response :unauthorized
    end
  end

  test "a conexão do WebSocket também recusa a sessão parada por 30 minutos (R28)" do
    entrar users(:joana).email_address, "senha-de-teste-1"
    session = Session.sole
    assert_not session.expired?
    travel 31.minutes do
      assert_predicate session.reload, :expired?
    end
  end

  test "muitas tentativas em pouco tempo recebem 429 com a mensagem" do
    11.times { entrar users(:joana).email_address, "errada" }

    assert_response :too_many_requests
    assert_equal "Muitas tentativas. Aguarde alguns minutos.", mensagem
  end
end
