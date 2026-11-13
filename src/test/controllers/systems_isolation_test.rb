require "test_helper"

# Isolamento (V10) nas escolhas e telas do incremento 17: o id de um sistema ou de um contrato de outro credor, escrito à mão no pedido, nunca vale; e a
# operação não abre a tela de sistemas nem acha, pelo id remoto, o cliente que não está pra ela (decisão 0024).
class SystemsIsolationTest < ActionDispatch::IntegrationTest
  include CsvHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "natural")
    @totvs = SourceSystem.create!(tenant: @beta, name: "Totvs", key_kind: "natural")
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "V10, R400: o envio da carteira não aceita o sistema de outro credor" do
    entrar(users(:joana))

    assert_no_difference -> { Import.count } do
      post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental", source_system_id: @totvs.id, file: fixture_file_upload(write_csv([ csv_line ]), "text/csv") } }, headers: TRECHO
    end
    assert_response :unprocessable_content
    assert_includes response.body, "Escolha o sistema."
    assert_select "select[name='import[source_system_id]'] option", text: "Totvs", count: 0
  end

  test "V10, R420: o sistema de outro credor no endereço da simulação não escolhe nada, e a tela pergunta de novo" do
    travel_day(AGREEMENT_DAY)
    customer, = agreement_scenario(@alfa)
    contract = Contract.create!(tenant: @alfa, source_system: @sap, code: "K-5")
    ContractCustomer.create!(contract: contract, customer: customer)
    Bill.create!(tenant: @alfa, contract: contract, customer: customer, number: "NF-3", due_date: Date.new(2026, 9, 15), amount_cents: 30_000, status: :active)
    entrar(users(:carlos))

    get new_customer_agreement_simulation_path(customer, sistema: @totvs.id), headers: TRECHO
    assert_response :success
    assert_select "h2", text: /De qual sistema são os títulos do acordo\?/
    assert_select "input[name='agreement[bill_ids][]']", count: 0
    assert_not_includes response.body, "Totvs"
  ensure
    travel_back
  end

  test "V10, R421: o contrato de outro credor não vale como o escolhido, na distribuição nem na transferência de crédito" do
    operation = make_operation(@alfa)
    accreditation = Accreditation.find_by!(tenant: @alfa, operation: operation)
    ana = make_customer(@alfa, document: FakeData.cpf(401), name: "Ana Lima", contract_code: "C-7")
    twin = Contract.create!(tenant: @alfa, source_system: @sap, code: "C-7")
    ContractCustomer.create!(contract: twin, customer: make_customer(@alfa, document: FakeData.cpf(402), name: "Bia Reis", contract_code: "C-8"))
    foreign = make_bill(@beta, number: "NF-9", contract_code: "C-7").contract
    entrar(users(:joana))

    assert_no_difference -> { Distribution.count } do
      post distributions_path, params: { distribution: { accreditation_id: accreditation.id, target: "contract", value: "C-7", contract_id: foreign.id, exposure: "overdue",
                                                         starts_on: Date.current.iso8601 } }, headers: TRECHO
    end
    assert_response :unprocessable_content
    assert_select "input[type=radio][name='distribution[contract_id]']", 2
    assert_select "input[type=radio][value='#{foreign.id}']", count: 0

    # Na transferência, o código C-8 tem um contrato só neste credor: vale ele, e o contrato de outro credor informado como escolhido é ignorado.
    from = ana.contracts.sole
    to = Contract.find_by!(tenant: @alfa, code: "C-8")
    Credit.create!(tenant: @alfa, contract: from, kind: :entry, amount_cents: 20_000, reason: :excess)
    post customer_credit_transfers_path(ana), params: { credit_transfer: { from_contract_id: from.id, to_code: "C-8", to_contract_id: foreign.id, amount: "150,00", reason: "migração" } }, headers: TRECHO
    assert_equal [ 5_000, 15_000, 0 ], [ from.credit_cents, to.credit_cents, foreign.reload.credit_cents ]
  end

  test "V10 e 0024: a operação não abre a tela de sistemas e só acha pelo id remoto o cliente que está pra ela" do
    operation = make_operation(@alfa)
    caio = make_operation_user(operation, @alfa)
    ana = make_customer(@alfa, document: FakeData.cpf(401), name: "Ana Lima", contract_code: "C-7")
    bia = make_customer(@alfa, document: FakeData.cpf(402), name: "Bia Reis", contract_code: "C-8")
    CustomerIdentity.create!(tenant: @alfa, source_system: @sap, customer: ana, external_id: "BP-1")
    CustomerIdentity.create!(tenant: @alfa, source_system: @sap, customer: bia, external_id: "BP-2")
    Distribution.create!(tenant: @alfa, operation: operation, customer: ana, exposure: "all", starts_on: Date.current - 1)
    Operations::ReachBuilder.new(@alfa).rebuild
    entrar(caio)

    get source_systems_path, headers: TRECHO
    assert_response :not_found
    assert_equal [ "Ana Lima" ], linhas_de_clientes(busca: "BP-1").map { |linha| celula(linha, "name") }
    assert_empty linhas_de_clientes(busca: "BP-2"), "a identidade do cliente que não está pra operação não existe pra ela"
  end
end
