require "application_system_test_case"

# Redesenho denso e corporativo (fase 1, decisão 0022): as cinco telas do protótipo no axe, nenhuma tela rola na horizontal a 1440, 1024 e 390 px, e as medidas da
# revisão 4 (cabeçalho de 56 px, controle de 34 px, linha de 36 px), com o menu de 256 px da revisão 6.
class RedesignScreensSystemTest < ApplicationSystemTestCase
  LARGURAS = [ 1440, 1024, 390 ].freeze

  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321")
    add_contact(@maria, "email", "maria@exemplo.com.br")
  end

  def entrar
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1")
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal(rota)
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"), "#{rota} rola na horizontal a #{page.evaluate_script('window.innerWidth')} px"
  end

  def medida(seletor, propriedade = "height") = page.evaluate_script("Math.round(document.querySelector(#{seletor.to_json}).getBoundingClientRect().#{propriedade})")

  test "a entrada (formulário à esquerda e apresentação à direita) passa no axe e não rola em nenhuma largura" do
    LARGURAS.each do |largura|
      page.driver.resize(largura, 900)
      visit root_path
      assert_selector "h1", text: "Entrar no CRM", wait: 30
      sem_rolagem_horizontal("/")
      assert_acessivel if largura == 1440
    end
    page.driver.resize(1440, 900)
    visit root_path
    assert_selector ".entrada-beneficios > *", count: 4, wait: 30
    assert_operator page.evaluate_script("document.querySelector('.entrada-formulario').getBoundingClientRect().left"), :<, page.evaluate_script("document.querySelector('.entrada-apresentacao').getBoundingClientRect().left")
    assert_equal 480, medida(".entrada-formulario", "width")
    # Janela baixa (1366×768 menos o navegador, ou tablet deitado): o título não encolhe e "Entrar" aparece inteiro (design system, 17.5).
    page.driver.resize(1366, 500)
    visit root_path
    assert_selector "h1", text: "Entrar no CRM", wait: 30
    assert_operator medida("h1"), :>=, 30
    assert_operator page.evaluate_script("Math.round([...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Entrar').getBoundingClientRect().bottom)"), :<=, 500
    page.driver.resize(390, 900)
    visit root_path
    assert_selector "h1", text: "Entrar no CRM", wait: 30
    assert_no_selector ".entrada-apresentacao", visible: :visible
  end

  test "as cinco telas do protótipo passam no axe" do
    entrar
    [ root_path, customers_path, customer_path(@maria), settings_portfolio_path ].each do |rota|
      visit rota
      assert_selector "h1"
      assert_acessivel
    end
    visit customer_path(@maria)
    click_link "Registrar acionamento"
    assert_selector "dialog#painel[open] form.painel"
    assert_acessivel
  end

  test "as medidas da revisão 4: cabeçalho de 56 px, controle de 34 px, linha de 36 px e menu de 256 px (revisão 6)" do
    entrar
    visit customers_path
    assert_selector "#resultado tbody tr"
    assert_equal 56, medida("body > header")
    assert_equal 256, medida("body > nav", "width")
    assert_equal 34, medida("form.filtros select")
    assert_equal 36, medida("#resultado tbody tr")
    assert_equal 15, page.evaluate_script("parseFloat(getComputedStyle(document.body).fontSize)")
    visit customer_path(@maria)
    assert_equal 320, medida(".ficha-lateral", "width")
  end

  # Design system, revisão 6: nenhum rótulo do menu quebra em duas linhas, nem com o selo de contagem, nem no submenu da configuração aberto.
  test "todo item do menu cabe em uma linha" do
    bill = @maria.bills.first
    ValueDiscrepancy.create!(tenant: @alfa, bill: bill, previous_cents: 1, reported_cents: 2, allocated_cents: 1, balance_before_cents: 0, balance_after_cents: 0,
                             effect: "record_only", policy: "keep", status: "open")
    entrar
    visit settings_contact_results_path
    assert_selector "#menu-principal details.submenu[open]"
    assert_selector "#menu-principal .selo"
    altura = page.evaluate_script("parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--altura-item-menu')) * parseFloat(getComputedStyle(document.documentElement).fontSize)")
    itens = page.evaluate_script("[...document.querySelectorAll('#menu-principal a, #menu-principal summary')].map((el) => [el.textContent.trim().replace(/\\s+/g, ' '), el.getBoundingClientRect().height])")
    altos = itens.select { |_, h| h > altura + 1 }
    assert_empty altos, "itens do menu em mais de uma linha: #{altos.map(&:first).join(', ')}"
  end

  test "nenhuma tela rola na horizontal a 1440, 1024 e 390 px" do
    entrar
    rotas = [ root_path, customers_path, customer_path(@maria), customer_path(@maria, aba: "acionamentos"), customer_path(@maria, aba: "contatos"), customer_path(@maria, aba: "pagamentos"),
              customer_path(@maria, aba: "historico"), contact_attempts_path, imports_path, new_import_path, new_import_path(kind: "payments"), value_discrepancies_path, agreements_path,
              pending_promises_path, pending_agreements_path, data_retention_path, settings_tenant_registry_path, settings_portfolio_path, settings_channels_path,
              settings_payment_policy_path, settings_payment_accounts_path, settings_segments_path, settings_promises_path, settings_indexes_path, settings_contact_results_path ]
    LARGURAS.each do |largura|
      page.driver.resize(largura, 900)
      rotas.each do |rota|
        visit rota
        assert_selector "h1"
        sem_rolagem_horizontal(rota)
      end
    end
  end

  test "a busca global do cabeçalho leva à lista de clientes filtrada" do
    entrar
    fill_in "Buscar cliente por nome ou documento", with: "Maria"
    find(".busca button").click
    assert_selector "h1", text: "Clientes"
    assert_selector "#resultado tbody tr", count: 1
  end
end
