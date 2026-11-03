require "test_helper"

# As telas da SPA das fases F a H (decisão 0025): cada uma abre pelo JSON da mesma rota, com as chaves que a view usa, e quem não tem a permissão recebe 404.
class SpaScreensJsonTest < ActionDispatch::IntegrationTest
  def entrar(usuario) = post(session_path, params: { email_address: usuario.email_address, password: "senha-de-teste-1" })

  test "as telas de configuração e administração respondem JSON ao gestor" do
    entrar(users(:joana))
    {
      settings_tenant_registry_path => "credores", settings_portfolio_path => "credores", settings_channels_path => "linhas",
      settings_payment_policy_path => "credores", settings_segments_path => nil, memberships_path => "linhas", profiles_path => "linhas",
      data_retention_path => "prazos", imports_path => "linhas", distributions_path => "linhas"
    }.each do |caminho, chave|
      get "#{caminho}.json"
      assert_response :success, caminho
      assert response.parsed_body.key?(chave), "#{caminho} sem #{chave}" if chave
    end
  end

  test "a recusa de um formulário vem em JSON com a mensagem (422)" do
    entrar(users(:joana))
    patch settings_portfolio_path, params: { tenant_id: tenants(:alfa).id, section: "brackets", brackets: [ { from: "5", to: "2" } ] }, as: :json
    assert_response :unprocessable_content
    assert response.parsed_body["mensagem"].is_a?(String)
  end

  test "a senha temporária do usuário novo vem uma vez na resposta" do
    entrar(users(:joana))
    perfil = tenants(:alfa).profiles.first
    post memberships_path, params: { membership: { tenant_id: tenants(:alfa).id, email_address: "nova.pessoa@exemplo.com.br", name: "Nova Pessoa", profile_id: perfil.id } }, as: :json
    assert_response :success
    assert_equal "nova.pessoa@exemplo.com.br", response.parsed_body.dig("senha_temporaria", "email")
    get memberships_path(format: :json)
    assert_nil flash[:temporary_password]
  end

  test "o operador sem permissão não abre as telas de administração em JSON" do
    entrar(users(:carlos))
    [ memberships_path, profiles_path, settings_channels_path ].each do |caminho|
      get "#{caminho}.json"
      assert_response :not_found, caminho
    end
  end
end
