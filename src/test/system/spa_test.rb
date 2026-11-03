require "application_system_test_case"

# A SPA em OpenUI5 (decisão 0025): entrada, casca com menu e abas da aplicação (P27), lista de clientes e ficha numa aba.
class SpaSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @maria = Customer.create!(tenant: @alfa, document: "52998224725", name: "Maria Souza")
    contrato = Contract.create!(tenant: @alfa, code: "C-1")
    ContractCustomer.create!(contract: contrato, customer: @maria, roles: %w[holder financial_responsible])
    Bill.create!(tenant: @alfa, contract: contrato, customer: @maria, number: "T1", due_date: Date.current - 40, amount_cents: 10_000)
    @jose = Customer.create!(tenant: @alfa, document: "39053344705", name: "José Lima")
    outro = Contract.create!(tenant: @alfa, code: "C-2")
    ContractCustomer.create!(contract: outro, customer: @jose, roles: %w[holder financial_responsible])
    Bill.create!(tenant: @alfa, contract: outro, customer: @jose, number: "T2", due_date: Date.current - 10, amount_cents: 5_000)
  end

  test "a senha errada mostra a mensagem de sempre, e a certa abre a casca com o menu da pessoa" do
    visit root_path
    find("input[type=email]", wait: 30)
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "errada"
    click_button "Entrar"
    assert_text "E-mail ou senha incorretos."

    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1", destino: nil)
    assert_text "Resumo da carteira"
    assert_text "Clientes"
    assert_text users(:joana).name
    assert_acessivel
  end

  test "P27: a lista de clientes e cada ficha abrem numa aba; alternar não perde a busca; recarregar devolve as abas" do
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1", destino: nil)
    visit "/#/clientes"
    assert_text "Maria Souza", wait: 15
    assert_text "José Lima"

    find("input[type=search][placeholder='Nome, documento ou contrato']").set("Maria")
    assert_no_text "José Lima", wait: 10

    click_link "Maria Souza"
    assert_selector ".sapMTabStripItem", text: "Maria Souza", wait: 15
    assert_text "T1"
    assert_text "R$ 100,00"
    assert_acessivel

    find(".sapMTabStripItem", text: "Clientes").click
    assert_text "Maria Souza"
    assert_no_text "José Lima"
    assert_equal "Maria", find("input[type=search][placeholder='Nome, documento ou contrato']").value

    visit "/#/clientes"
    page.driver.refresh
    assert_selector ".sapMTabStripItem", text: "Maria Souza", wait: 20
    assert_selector ".sapMTabStripItem", text: "Clientes"
  end

  test "ficha: registrar acionamento pelo painel da aba e marcar um contato como inválido pelo modal" do
    contato = CustomerContact.create!(tenant: @alfa, customer: @maria, kind: "phone", value: "(11) 98888-0000", key: "11988880000", origin: "screen", status: "valid")
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1", destino: nil)
    visit "/#/clientes/#{@maria.id}"
    assert_text "T1", wait: 15
    esperar_a_spa

    click_button "Registrar acionamento"
    assert_selector ".painel", text: "Canal", wait: 10
    find("[id$='--canal']").click
    find(".sapMSelectList li", text: "Telefone").click
    find("[id$='--resultado']").click
    find(".sapMSelectList li", text: contact_results(:alfa_no_answer).name).click
    within(".painel") { click_button "Registrar acionamento" }
    assert_text "Acionamento registrado.", wait: 10
    assert_equal 1, ContactAttempt.where(customer: @maria).count
    esperar_a_spa

    find(".sapMITBFilter", text: "Contatos").click
    find(".sapMListTblRow", text: contato.value).find("button[title='Ações da linha']").click
    find(".sapMMenuItem, .sapUiMnuItm", text: "Marcar como inválido").click
    fill_in "Motivo", with: "número de outra pessoa"
    within(".sapMDialog") { click_button "Marcar como inválido" }
    assert_text "Inválido", wait: 10
    assert_predicate contato.reload, :status_invalid?
  end

  test "o Resumo abre na entrada e a lista de acionamentos abre numa aba, as duas no axe" do
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1", destino: nil)
    assert_text "Resumo da carteira", wait: 15
    assert_text "Clientes em cobrança"
    esperar_a_spa
    assert_acessivel

    visit "/#/acionamentos"
    assert_selector ".sapMTabStripItem", text: "Acionamentos", wait: 15
    assert_text "Nenhum acionamento no período."
    esperar_a_spa
    assert_acessivel
  end
end
