require "application_system_test_case"

# Promessas no navegador (10): o bloco do formulário reage ao resultado e mostra o valor antes de gravar, a linha no cabeçalho da ficha, a lista de pendentes,
# a aba de configuração e o painel, todos no axe e sem rolagem horizontal.
class PromisesScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    PromiseLimit.where(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_manager)).update_all(max_days: 60)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  # Campo de data do navegador: grava o valor e avisa a mudança, como quem escolhe a data no calendário.
  def choose_date(id, date)
    find("##{id}").set(date)
    page.execute_script("document.getElementById('#{id}').dispatchEvent(new Event('change', { bubbles: true }))")
  end

  # Espera o htmx terminar o pedido em andamento (o bloco da promessa é refeito pelo servidor a cada mudança).
  def wait_htmx = assert_no_selector(".htmx-request")

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "o formulário mostra o bloco da promessa, o valor de cada título, e registra a promessa; a ficha mostra a linha" do
    visit customer_path(@customer, aba: "promessas")
    click_link "Registrar acionamento"
    assert_selector "dialog#painel[open]"
    assert_no_selector "#bloco-promessa"
    within("#painel") do
      select "Prometeu pagar", from: "Resultado"
      wait_htmx
      assert_selector "#bloco-promessa legend", text: "Registrar promessa"
      select "Telefone", from: "Canal"
      wait_htmx
      select "CT-1", from: "Contrato da promessa"
      wait_htmx
      assert_selector "#bloco-promessa input[type=checkbox]", count: 2
      check "NF-1, vence em 15/07/2026, saldo R$ 1.000,00"
      wait_htmx
      check "NF-2, vence em 15/09/2026, saldo R$ 500,00"
      wait_htmx
      select "Pix", from: "Meio de pagamento"
      wait_htmx
      choose_date("contact_attempt_promise_on", Date.current + 9)
      wait_htmx
      assert_selector "#bloco-promessa tfoot td", text: /R\$ \d/
    end
    assert_acessivel
    sem_rolagem_horizontal

    within("#painel") { click_button "Registrar acionamento" }
    assert_text "Acionamento registrado"
    assert_selector "ul.promessas li", text: /PRM-000001/
    assert_selector "ul.promessas li", text: /NF-1 e NF-2/
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "o formulário volta com o motivo quando a data passa do prazo máximo" do
    visit customer_path(@customer, aba: "promessas")
    click_link "Registrar acionamento"
    within("#painel") do
      select "Prometeu pagar", from: "Resultado"
      wait_htmx
      select "Telefone", from: "Canal"
      wait_htmx
      select "CT-1", from: "Contrato da promessa"
      wait_htmx
      check "NF-1, vence em 15/07/2026, saldo R$ 1.000,00"
      wait_htmx
      select "Pix", from: "Meio de pagamento"
      wait_htmx
      choose_date("contact_attempt_promise_on", Date.current + 120)
      wait_htmx
      click_button "Registrar acionamento"

      assert_text "A data prometida vai até"
      assert_checked_field "NF-1, vence em 15/07/2026, saldo R$ 1.000,00"
    end
    assert_equal 0, PaymentPromise.count
  end

  test "a promessa registrada por outro aparece ao vivo na ficha, pelo WebSocket, sem recarregar" do
    visit customer_path(@customer, aba: "promessas")
    assert_no_selector "ul.promessas"
    assert_selector "html[data-cable='conectado']"
    register_promise(@customer, [ @nf1 ], user: users(:carlos))
    assert_selector "ul.promessas li", text: /PRM-000001/, wait: 10
  end

  test "pendentes, aprovação, configuração e painel passam no axe" do
    register_promise(@customer, [ @nf1, @nf2 ], user: users(:carlos), on: Date.current + 45)
    visit pending_promises_path
    assert_selector "h1", text: "Promessas pendentes"
    assert_selector "tbody tr", count: 1
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Aprovar", match: :first
    assert_text "Promessa PRM-000001 aprovada."
    visit customer_path(@customer, aba: "promessas")
    assert_selector "ul.promessas li", text: /Aberta/
    find("ul.promessas button.menu-de-linha").click
    assert_selector "a", text: "Cancelar promessa"
    assert_acessivel

    visit settings_promises_path
    assert_selector "h1", text: "Promessas"
    assert_selector "h2", text: /Prazo máximo e alçada/
    assert_acessivel
    sem_rolagem_horizontal

    visit root_path
    assert_selector "h2", text: "Promessas"
    assert_acessivel
    visit settings_contact_results_path
    assert_selector "th", text: "Admite promessa"
    assert_acessivel
  end
end
