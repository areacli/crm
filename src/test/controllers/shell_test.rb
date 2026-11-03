require "test_helper"

# A casca da SPA e os módulos da aplicação OpenUI5 (decisão 0025).
class ShellTest < ActionDispatch::IntegrationTest
  test "a casca é pública: carrega o OpenUI5 do próprio servidor, sem sessão não traz usuário, e a CSP não tem unsafe-eval" do
    get root_url

    assert_response :success
    assert_select "script#sap-ui-bootstrap[src='/ui5/#{Ui5App.openui5}/resources/sap-ui-core.js'][data-sap-ui-async=true][data-sap-ui-theme=sap_horizon]"
    configuracao = JSON.parse(css_select("#configuracao-da-casca").text)
    assert_nil configuracao["usuario"]
    assert_equal "/crm/#{Ui5App.versao}", configuracao["aplicacao"]
    politica = response.headers["Content-Security-Policy"]
    assert_includes politica, "script-src 'self'"
    assert_not_includes politica, "unsafe-eval"
  end

  test "com sessão, a casca traz o usuário" do
    sign_in_as users(:joana)
    get root_url

    configuracao = JSON.parse(css_select("#configuracao-da-casca").text)
    assert_equal users(:joana).name, configuracao.dig("usuario", "nome")
    assert_equal false, configuracao.dig("usuario", "senha_temporaria")
  end

  test "os módulos vêm com cache longo na versão certa, e nada fora da pasta da aplicação" do
    get ui5_app_url(versao: Ui5App.versao, caminho: "manifest.json")
    assert_response :success
    assert_equal "crm", response.parsed_body.dig("sap.app", "id")
    assert_includes response.headers["Cache-Control"], "immutable"

    get "/crm/#{Ui5App.versao}/../../config/database.yml"
    assert_response :not_found
    get "/crm/#{Ui5App.versao}/servico/naoexiste.js"
    assert_response :not_found
  end

  test "o pacote de pré-carga traz o código como função (sem eval) e as views como texto" do
    get ui5_app_url(versao: Ui5App.versao, caminho: "Component-preload.js")

    assert_response :success
    assert_includes response.body, "sap.ui.require.preload({"
    assert_includes response.body, %("crm/Component.js":function(){)
    assert_includes response.body, %("crm/view/Entrada.view.xml":")
  end

  test "a versão do OpenUI5 do bootstrap é a do instalador" do
    assert_equal Rails.root.join("config/ui5_versao").read.strip, Ui5App.openui5
    assert_includes Rails.root.join("bin/ui5-instalar").read, %(config/ui5_versao)
  end

  test "o menu em JSON tem os grupos e itens que a pessoa pode ver" do
    sign_in_as users(:joana)
    get menu_url(format: :json)

    assert_response :success
    rotulos = response.parsed_body["secoes"].flat_map { |secao| secao["itens"].map { |item| item["rotulo"] } }
    assert_includes rotulos, "Clientes"
    assert_includes rotulos, "Configuração"
    assert_equal true, response.parsed_body["busca"]
  end
end
