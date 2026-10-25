require "test_helper"

# Telas da carteira revista (05): divergências de valor (permissão 6 por credor, V10), histórico do título, ficha, conferência e política.
class DiscrepanciesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    @alfa_discrepancy = ValueDiscrepancy.sole
    @beta_bill = paid_bill(tenant: @beta, number: "NF-B", document: JOAO, contract_code: "CT-B", name: "João Beta")
    run_portfolio_import([ bill_line("NF-B", "300,00", "documento" => JOAO, "nome" => "João Beta", "contrato" => "CT-B") ], tenant: @beta, confirm: true)
    @beta_discrepancy = ValueDiscrepancy.where(tenant: @beta).sole
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "operador não vê a lista nem o item do menu (404 registrado)" do
    entrar(users(:carlos))
    get root_path
    assert_select "nav a", text: /Divergências de valor/, count: 0
    get value_discrepancies_path
    assert_response :not_found
    get value_discrepancy_path(@alfa_discrepancy)
    assert_response :not_found
    assert_operator AccessEvent.where(event: "access_denied").count, :>=, 2
  end

  test "critério da Marta: só a divergência do credor da permissão, com o número do menu, e o link direto do outro é recusado (V10)" do
    marta = users(:marta)
    Membership.find_by!(user: marta, tenant: @beta).profile.update!(permissions: %w[view_portfolio confirm_payments])
    marta_alfa = make_user(@alfa, [], email: "marta2@exemplo.com.br") # só consultar na Alfa
    Membership.create!(user: marta, tenant: @alfa, profile: marta_alfa.memberships.first.profile)
    entrar(marta)
    get value_discrepancies_path
    assert_response :success
    assert_select "th a", text: "NF-B"
    assert_select "th a", text: "NF-1024/3", count: 0
    assert_select "nav a", text: "Divergências de valor (1)"
    get value_discrepancy_path(@alfa_discrepancy)
    assert_response :not_found
    assert_equal @alfa.id, AccessEvent.where(event: "access_denied").last.tenant_id
    post value_discrepancy_handling_path(@alfa_discrepancy), params: { handling: { note: "x", choice: "keep" } }
    assert_response :not_found
    assert_predicate @alfa_discrepancy.reload, :open?
  end

  test "quem trata nos dois credores vê os dois, com a coluna Credor e o filtro" do
    user = users(:joana)
    Membership.create!(user: user, tenant: @beta, profile: profiles(:beta_manager))
    entrar(user)
    get value_discrepancies_path
    assert_select "th", text: "Credor"
    assert_select "th a", count: 2
    get value_discrepancies_path(tenant: @beta.id)
    assert_select "th a", text: "NF-B"
    assert_select "th a", text: "NF-1024/3", count: 0
  end

  test "tratar sem nota é recusado; com nota e manter passa a tratada" do
    entrar(users(:joana))
    get value_discrepancy_path(@alfa_discrepancy)
    assert_response :success
    assert_select "button", text: "Tratar divergência"
    assert_select "input[value=apply]", count: 0 # política seguir: não há o que aplicar
    post value_discrepancy_handling_path(@alfa_discrepancy), params: { handling: { note: " ", choice: "keep" } }
    assert_redirected_to value_discrepancy_path(@alfa_discrepancy)
    follow_redirect!
    assert_select "aside", text: /Informe a nota/
    assert_predicate @alfa_discrepancy.reload, :open?

    post value_discrepancy_handling_path(@alfa_discrepancy), params: { handling: { note: "conferido com o credor", choice: "keep" } }
    follow_redirect!
    assert_select "aside", text: /Divergência tratada/
    assert_select "dd", text: "conferido com o credor"
    assert_predicate @alfa_discrepancy.reload, :handled?
    get value_discrepancies_path
    assert_select "td", text: /Nenhuma/, count: 0
    assert_select "p.vazio", text: /Nenhuma divergência aberta/
  end

  test "na política manter e registrar a opção aplicar aparece, e título pago não a oferece" do
    set_discrepancy_policy("keep")
    other = paid_bill(number: "NF-K", document: JOAO, contract_code: "CT-K", name: "João K")
    run_portfolio_import([ bill_line("NF-K", "300,00", "documento" => JOAO, "nome" => "João K", "contrato" => "CT-K") ], confirm: true)
    entrar(users(:joana))
    get value_discrepancy_path(ValueDiscrepancy.find_by!(bill: other))
    assert_select "input[value=apply]"
    get value_discrepancy_path(@alfa_discrepancy) # nasceu na política seguir
    assert_select "input[value=apply]", count: 0
  end

  test "histórico do título e ficha: Valor, Pago e Saldo e o aviso da divergência aberta" do
    entrar(users(:joana))
    get customer_path(@bill.customer)
    assert_response :success
    assert_select "th", text: "Pago"
    assert_select "small", text: /Divergência de valor aberta/
    assert_select "h3", text: /CT-1: R\$ 100,00/ # crédito do contrato: excedente de R$ 100,00
    assert_select "td", text: /Valor do título reduzido/
    get bill_path(@bill)
    assert_response :success
    assert_select "h2", text: "Versões do valor"
    assert_select "tbody tr", minimum: 4
    assert_select "td", text: /Divergência: o credor informou outro valor/
    get bill_path(@beta_bill)
    assert_response :not_found
  end

  test "operador sem acesso ao credor não abre o histórico de outro credor" do
    entrar(users(:marta))
    get bill_path(@beta_bill)
    assert_response :success
    get bill_path(@bill)
    assert_response :not_found
  end

  test "conferência mostra a seção de divergências e os acréscimos informados" do
    set_discrepancy_policy("follow")
    paid_bill(number: "NF-C", document: JOAO, contract_code: "CT-C", name: "João C")
    header = CsvHelper::HEADER + %w[multa_credor]
    checked = run_portfolio_import([ bill_line("NF-C", "300,00", "documento" => JOAO, "nome" => "João C", "contrato" => "CT-C", "multa_credor" => "20,00") ], header: header)
    entrar(users(:joana))
    get import_path(checked)
    assert_select "h2", text: "Divergências de valor: 1 título"
    assert_select "td", text: "Passa a pago"
    assert_select "h2", text: "Acréscimos informados pelo credor"
  end

  test "política de divergência: a 14 altera e registra; sem a 14 aparece como texto, e o envio é recusado" do
    entrar(users(:joana))
    get settings_portfolio_path
    assert_select "input[name=discrepancy_policy]", count: 2
    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "discrepancy", discrepancy_policy: "keep" }
    assert_equal "keep", @alfa.setting.reload.discrepancy_policy
    assert_equal "discrepancy_policy_changed", Change.where(subject_type: "settings", subject_id: @alfa.id).last.event

    gestor = make_user(@alfa, %w[change_settings], email: "so4@exemplo.com.br")
    delete session_path
    entrar(gestor)
    get settings_portfolio_path
    assert_select "input[name=discrepancy_policy]", count: 0
    assert_select "span.situacao", text: "Escolha atual"
    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "discrepancy", discrepancy_policy: "follow" }
    assert_response :not_found
    assert_equal "keep", @alfa.setting.reload.discrepancy_policy
  end

  test "o menu mostra o número das divergências abertas do gestor" do
    entrar(users(:joana))
    get root_path
    assert_select "nav a", text: "Divergências de valor (1)"
  end
end
