require "application_system_test_case"

# Acionamentos no navegador: ficha com o formulário que reage ao resultado, lista, resumo e resultados, todos no axe.
class ContactAttemptsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321")
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    ContractCustomer.where(customer: @maria).update_all(roles: %w[holder financial_responsible])
    ContractCustomer.where(customer: pedro).update_all(roles: %w[holder])
    @pedro = pedro
    insert_attempt(@maria, user: users(:carlos), result: result_of(@alfa, :negotiating), text: "Quer parcelar em três vezes.\nRetornar na sexta.", contacted_at: 2.hours.ago)
    insert_attempt(@maria, user: users(:joana), result: result_of(@alfa, :voicemail), channel: "whatsapp", contacted_at: 5.hours.ago)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "ficha com acionamentos, a lista, o resumo e os resultados passam no axe" do
    visit customer_path(@maria)
    assert_selector "h2", text: "Acionamentos"
    assert_selector "h3", text: "Registrar acionamento"
    assert_text "Quer parcelar em três vezes."
    assert_acessivel
    sem_rolagem_horizontal

    visit contact_attempts_path
    assert_selector "h1", text: "Acionamentos"
    assert_selector "#resultado tbody tr", count: 2
    assert_acessivel
    sem_rolagem_horizontal

    visit root_path
    assert_selector "h2", text: "Acionamentos"
    assert_acessivel

    visit settings_contact_results_path
    assert_selector "h1", text: "Resultados de acionamento"
    assert_acessivel
    click_link "Novo resultado"
    assert_selector "h1", text: "Novo resultado de acionamento"
    assert_acessivel
    visit edit_settings_contact_result_path(result_of(@alfa, :voicemail))
    assert_acessivel
  end

  test "o campo de retorno aparece conforme o resultado e o registro entra no histórico sem recarregar a página" do
    visit customer_path(@pedro)
    select "Telefone", from: "Canal"
    select "Pediu para retornar depois", from: "Resultado"
    assert_field "Retorno combinado", type: "datetime-local"
    assert find_field("Retorno combinado")[:required]

    select "Número ou endereço inexistente", from: "Resultado"
    assert_no_field "Retorno combinado"

    select "Negociação em andamento", from: "Resultado"
    assert_field "Retorno combinado (opcional)"

    select "CT-1", from: "Contrato (opcional)"
    assert_text "O responsável financeiro deste contrato é Maria Souza"
    fill_in "Texto (opcional)", with: "Pediu o boleto\npor e-mail"
    fill_in "Contato usado (opcional)", with: "(11) 3333-4444"
    marcador = page.evaluate_script("window.__sem_recarregar = 1")
    click_button "Registrar acionamento"

    assert_text "Acionamento registrado."
    assert_equal 1, page.evaluate_script("window.__sem_recarregar")
    within("#historico-acionamentos") do
      assert_text "Negociação em andamento"
      assert_text "(11) 3333-4444"
      assert_text "Contrato CT-1"
      assert_text "Pediu o boleto"
    end
    assert_equal "", find_field("Texto (opcional)").value
    assert_equal 1, @pedro.contact_attempts.count
    assert marcador
  end

  test "resultado que exige retorno sem a data: o navegador pede a data e o servidor também recusa" do
    visit customer_path(@pedro)
    select "Telefone", from: "Canal"
    select "Pediu para retornar depois", from: "Resultado"
    fill_in "Texto (opcional)", with: "texto que fica"
    # O atributo `required` barra o envio no navegador; tira-se para provar que o servidor recusa e devolve o formulário preenchido.
    assert_selector "#contact_attempt_return_at" # o campo chega por htmx depois de escolher o resultado
    page.execute_script("document.querySelector('#contact_attempt_return_at').required = false")
    click_button "Registrar acionamento"

    assert_text "Este resultado exige data de retorno."
    assert_equal "texto que fica", find_field("Texto (opcional)").value
    assert_equal 0, @pedro.contact_attempts.count
    assert_acessivel
  end

  test "a lista pelo filtro por operador e canal" do
    visit contact_attempts_path
    select "Carlos Lima", from: "Operador"
    assert_selector "#resultado tbody tr", count: 1
    select "Todos", from: "Operador"
    select "WhatsApp", from: "Canal"
    assert_selector "#resultado tbody tr", count: 1
    assert_text "Caixa postal"
  end
end
