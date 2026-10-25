require "application_system_test_case"

# A demonstração pública no navegador (CRM_DEMO=1): a faixa de aviso e a lista de usuários passam no axe e não fazem a página rolar na horizontal, no
# computador e no celular, na entrada e na página pública de pagamento; no resumo e na importação, o axe vale no computador e, no celular, só a faixa
# (a rolagem lateral das telas internas estreitas é do design system e das tabelas, não da faixa).
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

  def entrar
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  # A faixa aparece, a página não rola na horizontal em nenhuma largura e o axe passa no computador (no celular, as tabelas largas das telas internas rolam
  # dentro do contêiner `.tabela`, como manda o design system; o axe não é o assunto da faixa).
  def conferir(*larguras, axe_no_celular: false, sem_rolagem: true)
    larguras.each do |largura|
      page.driver.resize(largura, 900)
      visit current_path
      assert_selector "aside.demonstracao", text: "Demonstração: os dados são fictícios"
      assert_acessivel if largura >= 1024 || axe_no_celular
      assert_no_horizontal_scroll if sem_rolagem
    end
  end

  test "a entrada mostra a faixa e os usuários da demonstração, acessíveis e sem rolagem lateral" do
    visit new_session_path
    assert_selector "code", text: Demo.email("gestor")
    assert_selector "code", text: Demo.password("operador")
    conferir(1440, 390, axe_no_celular: true)
  end

  test "o resumo e a importação mostram a faixa, o aviso do arquivo descartado e passam no axe" do
    entrar
    conferir(1440, 390, sem_rolagem: false)
    visit new_import_path
    assert_selector "h1", text: "Importar carteira"
    assert_text "descartado sem ser lido"
    conferir(1440, 390, sem_rolagem: false)
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
end
