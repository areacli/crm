require "test_helper"

# Menu lateral por tipo de trabalho (padrões de interface, revisão 22): Cobrança, Financeiro, Entrada de dados, Operações de cobrança e
# Administração; as cargas são botões da página Importações, e as páginas das operações são o submenu do item "Operações", fora da configuração.
class NavigationMenuTest < ActionDispatch::IntegrationTest
  test "o gestor vê os grupos na ordem, sem os itens Importar e sem a seção Operações na configuração" do
    sign_in_as users(:joana)
    get root_url
    assert_equal [ "Cobrança", "Financeiro", "Entrada de dados", "Operações de cobrança", "Administração" ], css_select("#menu-principal h2").map { |h| h.text.strip }
    assert_select "#menu-principal a", text: /\AImportar/, count: 0
    assert_select "#menu-principal a", text: "Importações"
    assert_select "#menu-principal a", text: "Estornos à espera"
    assert_select "#menu-principal details.submenu:not([open]) summary", text: "Operações"
    %w[Credenciadas Trilha].each { |label| assert_select "#menu-principal details.submenu a", text: label }
    assert_select "#menu-principal details.submenu a", text: "Enquadramento da distribuição"
    assert_select "#menu-principal details.submenu a[href^='/configuracao']", text: "Operações", count: 0
  end

  test "nas páginas das operações o submenu Operações vem aberto com a página atual, e a Configuração fechada" do
    sign_in_as users(:joana)
    get settings_operation_trails_url
    assert_response :success
    assert_select "#menu-principal details.submenu[open] a[aria-current=page]", text: "Trilha"
    assert_select "#menu-principal a[aria-current=page]", text: "Credenciadas", count: 0
    assert_select "#menu-principal details.submenu:not([open]) summary", text: "Configuração"
    get settings_distribution_rules_url(tenant_id: tenants(:alfa).id)
    assert_select "#menu-principal details.submenu[open] a[aria-current=page]", text: "Enquadramento da distribuição"
  end

  test "a página de carga marca Importações e tem os botões de cada carga" do
    sign_in_as users(:joana)
    get new_import_url(kind: "payments")
    assert_select "#menu-principal a[aria-current=page]", text: "Importações"
    get imports_url
    %w[carteira pagamentos estornos].each { |kind| assert_select "main a.botao", text: "Importar #{kind}" }
  end

  test "o operador vê só o grupo Cobrança" do
    sign_in_as users(:carlos)
    get root_url
    assert_equal [ "Cobrança" ], css_select("#menu-principal h2").map { |h| h.text.strip }
  end
end
