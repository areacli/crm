require "test_helper"

# Páginas de erro do sistema (exceptions_app): conteúdo em pt-BR, no layout de erro, sem depender de sessão nem de banco.
class ErrorsControllerTest < ActionDispatch::IntegrationTest
  { 400 => "Pedido inválido", 404 => "Página não encontrada", 406 => "Navegador não suportado", 422 => "Não foi possível concluir",
    429 => "Muitas tentativas", 500 => "Algo deu errado do nosso lado", 503 => "Sistema indisponível" }.each do |status, title|
    test "a página de #{status} tem título e volta ao início, sem sessão" do
      get "/#{status}"

      assert_response status
      assert_select "h1", title
      assert_select "a[href='/']"
      assert_select "nav", false # sem menu
    end
  end

  test "a página de erro 500 mostra o código do pedido, e as outras não" do
    get "/500"
    assert_select "code"
    get "/404"
    assert_select "code", false
  end

  test "pedido que não é HTML recebe só o código" do
    get "/404", as: :json

    assert_response :not_found
    assert_empty response.body
  end

  test "código fora da lista não tem rota" do
    get "/418"

    assert_response :not_found
  end

  test "acesso recusado por permissão mostra a página de não encontrado no layout do app, e o htmx recebe só o código" do
    post session_path, params: { email_address: users(:carlos).email_address, password: "senha-de-teste-1" }
    get settings_portfolio_path

    assert_response :not_found
    assert_select "h1", "Página não encontrada"
    assert_select "nav[aria-label=Menu]" # o usuário continua no app

    get settings_portfolio_path, headers: { "HX-Request" => "true" }
    assert_response :not_found
    assert_empty response.body
  end

  # O caminho de produção: a exceção sai do app, o middleware reenvia para /<código> e o ErrorsController responde.
  def com_erros_de_producao
    env = Rails.application.env_config
    antes = env.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env["action_dispatch.show_exceptions"] = :all
    env["action_dispatch.show_detailed_exceptions"] = false
    yield
  ensure
    env.merge!(antes)
  end

  test "registro inexistente vira a página de não encontrado, em pt-BR" do
    post session_path, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    com_erros_de_producao { get customer_path(id: 0) }

    assert_response :not_found
    assert_select "h1", "Página não encontrada"
  end

  test "exceção sem tratamento vira a página de erro do servidor, com o código do pedido" do
    post session_path, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
    original = Portfolio::Summary.method(:new)
    Portfolio::Summary.define_singleton_method(:new) { |*| raise "falha de teste" }
    begin
      com_erros_de_producao { get root_path }
    ensure
      Portfolio::Summary.define_singleton_method(:new, original)
    end

    assert_response :internal_server_error
    assert_select "h1", "Algo deu errado do nosso lado"
    assert_select "code"
    assert_no_match(/falha de teste/, response.body) # a mensagem da exceção não vaza
  end
end
