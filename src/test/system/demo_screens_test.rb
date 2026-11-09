require "application_system_test_case"

# A demonstração pública no navegador (CRM_DEMO=1): a entrada da casca mostra os usuários da demonstração, a faixa de aviso fica no alto da casca,
# o celular vê o aviso de tela pequena com o endereço das telas no GitHub, e a página pública de pagamento passa no axe no computador e no celular.
class DemoScreensSystemTest < ApplicationSystemTestCase
  setup do
    @previous = Rails.configuration.x.demo.enabled
    Rails.configuration.x.demo.enabled = true
    @alfa = tenants(:alfa)
  end

  teardown do
    Rails.configuration.x.demo.enabled = @previous
    page.driver.resize(1440, 900)
  end

  def assert_no_horizontal_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "rolagem horizontal em #{page.current_path}"
  end

  test "a entrada mostra os usuários da demonstração sem rolagem lateral, e o celular vê o aviso com o endereço das telas" do
    visit root_path
    within("#entrada-form") do
      assert_selector "code", text: Demo.email("gestor")
      assert_selector "code", text: Demo.password("operador")
    end
    assert_acessivel
    assert_no_horizontal_scroll
    page.driver.browser.page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: true)
    visit root_path
    assert_selector "#aviso-tela a[href*='github.com/areacli/crm']"
    assert_no_horizontal_scroll
  ensure
    page.driver.browser.page.command("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  # O carrossel é só da demonstração: telas com legenda, navegação pelos botões, e cada usuário e senha numa linha, sem quebrar no meio.
  test "a entrada da demonstração mostra as telas em carrossel e as credenciais em linhas inteiras" do
    visit root_path
    assert_selector "[data-vitrine-tela][data-atual] figcaption", text: "O retrato da carteira"
    find("[data-vitrine-passo='1']").click
    assert_selector "[data-vitrine-tela][data-atual] figcaption", text: "Tudo de um cliente"
    find("[data-vitrine-ir='3']").click
    assert_selector "[data-vitrine-tela][data-atual] figcaption", text: "Simule o acordo"
    assert_acessivel
    alturas = page.evaluate_script("[...document.querySelectorAll('.entrada-demonstracao dd')].map((dd) => dd.getBoundingClientRect().height)")
    assert_operator alturas.max, :<, 22, "credencial quebrou de linha"
    assert_equal 6, alturas.size
  end

  test "fora da demonstração a entrada não tem carrossel" do
    Rails.configuration.x.demo.enabled = false
    visit root_path
    assert_selector "#entrada-form"
    assert_no_selector "[data-vitrine]"
  end

  test "a faixa fica no alto da casca, e a importação avisa que o arquivo é descartado" do
    entrar_na_casca
    assert_selector "#norte .faixa", text: "Demonstração: os dados são fictícios"
    visit new_import_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Importar carteira", wait: 15
    assert_text "descartado sem ser lido"
  end

  test "a página pública de pagamento mostra o aviso da demonstração e passa no axe" do
    make_channel(@alfa)
    checkout = make_checkout(customer: make_customer(@alfa), boleto: true, pix: true)
    visit checkout_path(checkout)
    assert_text "nenhum pagamento é real"
    assert_acessivel
    page.driver.resize(375, 800)
    visit checkout_path(checkout)
    assert_acessivel
    assert_no_horizontal_scroll
  end

  # A casca com a faixa cabe na janela baixa: as abas não passam do fim da janela e a página não rola; quem rola é o conteúdo da aba.
  test "a casca cabe na janela com a faixa, e o cabeçalho não rola com a aba" do
    entrar_na_casca
    page.driver.resize(1280, 640)
    visit settings_promises_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Promessas e acordos", wait: 15
    assert page.evaluate_script("document.querySelector('#abas').getBoundingClientRect().bottom <= window.innerHeight + 1"), "as abas passaram da janela"
    page.execute_script("window.scrollTo(0, 400)")
    assert_equal 0, page.evaluate_script("Math.round(document.querySelector('#norte').getBoundingClientRect().top)"), "o cabeçalho rolou com a página"
  end
end
