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
      assert_button "Gestor"
      assert_button "Operação terceirizada"
      find("summary", text: "Ver e-mails e senhas").click
      assert_selector "code", text: Demo.email("gestor")
      assert_selector "code", text: Demo.password("operador")
    end
    assert_link "Como foi feito, no Blog AreaCli", href: "https://blog.areacli.com/criei-um-crm/"
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

  # Padrões de interface, revisão 46: o botão do usuário da demonstração preenche o e-mail e a senha e entra pelo mesmo formulário.
  test "o botão do usuário da demonstração entra sem digitar" do
    # A senha pública fica de fora da regra de senha parecida com o e-mail, como na carga da demonstração (Demo::Dataset#public_user).
    gestor = User.new(name: "Gestor da demonstração", email_address: Demo.email("gestor"), password: Demo.password("gestor"))
    gestor.save!(validate: false)
    Membership.create!(user: gestor, tenant: @alfa, profile: profiles(:alfa_manager))
    visit root_path
    click_button "Gestor"
    assert_selector "#usuario", text: "Gestor da demonstração"
  end

  # O carrossel é só da demonstração: seis telas com nome, a régua primeiro, a escolha pelo nome, "Pausar" e a tela inteira sem rolar em 1.366 × 620.
  test "a entrada da demonstração mostra as telas em carrossel, com a régua primeiro, e cabe em 1.366 × 620" do
    page.driver.resize(1366, 620)
    visit root_path
    assert_selector ".vitrine-abas button[aria-current]", text: "Régua"
    assert_selector ".vitrine-legenda", text: "Régua de cobrança."
    click_button "Pagamento"
    assert_selector "[data-vitrine-tela][data-atual] img[alt^='Página de pagamento']"
    assert_selector ".vitrine-legenda", text: "Pix, boleto ou cartão"
    click_button "Pausar"
    assert_button "Continuar"
    assert_acessivel
    rola = page.evaluate_script("(() => { const e = document.querySelector('#entrada'); return e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth })()")
    assert_not rola, "a entrada rola em 1.366 × 620"
  end

  # Revisão 46, nota de 15/11/2026 (tablet em paisagem): numa janela mais baixa que o conteúdo, nada fica cortado; a entrada rola com as duas colunas,
  # e o lado marinho acompanha até a legenda. No Android, 100vh é a janela sem a barra do navegador, e a foto saía mais alta que a área visível; o
  # Chrome de mesa não tem essa barra, então o teste fixa a altura da foto como ela saía no tablet.
  test "na janela mais baixa que o conteúdo, o lado marinho não corta o título nem a legenda, e a entrada rola" do
    page.driver.resize(1280, 560)
    visit root_path
    assert_selector ".vitrine-abas button[aria-current]", text: "Régua"
    page.execute_script("document.head.insertAdjacentHTML('beforeend', '<style>.vitrine-palco { max-height: none !important; height: 420px }</style>')")
    assert_operator page.evaluate_script("document.querySelector('.entrada-tese').getBoundingClientRect().top"), :>=, 0, "o título do lado marinho começa acima da janela"
    page.execute_script("const e = document.querySelector('#entrada'); e.scrollTop = e.scrollHeight")
    medidas = page.evaluate_script(<<~JS)
      (() => { const r = (s) => document.querySelector(s).getBoundingClientRect();
        return { legenda: r('.vitrine-legenda').bottom, lado: r('.entrada-lado').bottom, rodape: r('.entrada-rodape').bottom, janela: innerHeight } })()
    JS
    assert_operator medidas["legenda"], :<=, medidas["janela"], "a legenda não aparece nem rolando"
    assert_operator medidas["legenda"], :<=, medidas["lado"], "a legenda passa do fundo marinho"
    assert_operator medidas["rodape"], :<=, medidas["janela"], "o rodapé da coluna branca não aparece nem rolando"
  end

  test "fora da demonstração a entrada é a tela dividida, sem carrossel nem usuários públicos" do
    Rails.configuration.x.demo.enabled = false
    visit root_path
    assert_selector "#entrada-form"
    assert_selector ".entrada-lado .entrada-titulo", text: "CRM de cobrança."
    assert_no_selector "[data-vitrine]"
    assert_no_selector "[data-entrar-como]"
  end

  test "a faixa fica no alto da casca, e a importação avisa que o arquivo é descartado" do
    entrar_na_casca
    assert_selector "#norte .faixa", text: "Demonstração: os dados são fictícios"
    visit new_import_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Importar carteira", wait: 15
    assert_text "descartado sem ser lido"
  end

  test "a página pública de pagamento mostra o aviso da demonstração e passa no axe" do
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
