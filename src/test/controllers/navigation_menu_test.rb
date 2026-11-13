require "test_helper"

# Menu lateral por tipo de trabalho (padrões de interface, revisão 22; na casca, revisão 38, P1): Resumo, Clientes e Acionamentos no grupo Geral; Cobrança,
# Financeiro, Entrada de dados, Distribuição e Administração; as cargas são botões da página Importações, e as páginas das operações são o submenu do item
# "Operações", fora da configuração. O menu vem no `menu.json`.
class NavigationMenuTest < ActionDispatch::IntegrationTest
  test "o gestor vê os grupos na ordem, sem os itens Importar e sem a seção Operações na configuração" do
    sign_in_as users(:joana)
    grupos = grupos_do_menu
    assert_equal [ "Geral", "Cobrança", "Financeiro", "Entrada de dados", "Distribuição", "Administração" ], grupos.keys
    assert_equal [ "Acordos" ], grupos["Cobrança"]
    assert_equal [ "Importações", "Sistemas" ], grupos["Entrada de dados"]
    assert_includes grupos["Financeiro"], "Estornos à espera"
    assert_empty grupos.values.flatten.grep(/\AImportar/)
    assert_equal [ "Credenciadas", "Enquadramento da distribuição", "Trilha" ], submenu_do_menu("Operações")
    assert_not_includes submenu_do_menu("Configuração"), "Operações"
  end

  # As páginas das operações estão na SPA (fase 6): o item marcado é da casca (`spa/aplicacao`); o `menu.json` traz o submenu Operações.
  test "o submenu Operações da casca traz Credenciadas, Enquadramento da distribuição e Trilha, e as páginas respondem como trechos" do
    sign_in_as users(:joana)
    get menu_path(format: :json)
    operacoes = response.parsed_body["grupos"].flat_map { |grupo| grupo["itens"] }.find { |item| item["rotulo"] == "Operações" }
    assert_equal [ "Credenciadas", "Enquadramento da distribuição", "Trilha" ], operacoes["subitens"].map { |item| item["rotulo"] }.sort
    get settings_operation_trails_url, headers: TRECHO
    assert_response :success
    assert_select "h1", text: "Trilha das operações"
    get settings_distribution_rules_url(credor: tenants(:alfa).id), headers: TRECHO
    assert_select "h1", text: "Enquadramento da distribuição"
  end

  # Importações estão na SPA (fase 5): o item do menu marcado é da casca (`spa/aplicacao`); o trecho tem os botões de cada carga.
  test "a página de importações tem os botões de cada carga" do
    sign_in_as users(:joana)
    get new_import_url(tipo: "pagamentos"), headers: TRECHO
    assert_response :success
    get imports_url, headers: TRECHO
    %w[carteira pagamentos estornos].each { |kind| assert_select ".cabecalho-da-pagina a.botao", text: "Importar #{kind}" }
  end

  test "o operador vê só o que é dele: Geral e o grupo Cobrança, com Acordos" do
    sign_in_as users(:carlos)
    assert_equal({ "Geral" => [ "Resumo", "Clientes", "Acionamentos" ], "Cobrança" => [ "Acordos" ] }, grupos_do_menu)
  end

  test "Clientes e Acionamentos ficam no grupo Geral, fora do grupo Cobrança, que só tem o que é da cobrança" do
    sign_in_as users(:joana)
    grupos = grupos_do_menu
    assert_equal [ "Resumo", "Clientes", "Acionamentos" ], grupos["Geral"]
    assert_empty grupos["Cobrança"] & [ "Clientes", "Acionamentos" ]
  end
end
