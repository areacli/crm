require "application_system_test_case"

# Operações no navegador (14): as telas do credor (credenciamento, distribuição, lote, enquadramento da distribuição, políticas, trilha) e as do
# usuário de operação (cabeçalho com a operação, lista e ficha só com o que está pra ele, pessoas da operação), todas no axe e sem rolagem horizontal.
class OperationsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    @caio = make_operation_user(@operation, @alfa, manager: true)
    @ana = make_customer(@alfa, document: FakeData.cpf(701), name: "Ana Distribuída", contract_code: "OP-1")
    @bia = make_customer(@alfa, document: FakeData.cpf(702), name: "Bia da Equipe", contract_code: "OP-2")
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: @operation, contract: Contract.find_by!(code: "OP-1"), exposure: "all",
                                                             starts_on: Date.current - 3)
    Operations::ReachBuilder.new(@alfa).rebuild
  end

  def entrar(user)
    visit new_session_path
    fill_in "E-mail", with: user.email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "header .usuario"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "as telas de operações do credor passam no axe" do
    entrar users(:joana)

    visit settings_operations_path
    assert_selector "h1", text: "Operações"
    assert_selector "td, th", text: "Recupera"
    assert_acessivel
    sem_rolagem_horizontal

    visit settings_operation_path(Accreditation.find_by!(tenant: @alfa, operation: @operation))
    assert_selector "h1", text: "Recupera"
    assert_acessivel

    visit new_settings_operation_path(tenant_id: @alfa.id)
    assert_selector "h1"
    assert_acessivel

    visit distributions_path
    assert_selector "h1", text: "Distribuição"
    assert_text "OP-1"
    assert_acessivel
    sem_rolagem_horizontal

    visit new_distribution_path
    assert_selector "h1"
    assert_acessivel

    visit new_distribution_batch_path
    assert_selector "h1"
    assert_acessivel

    visit settings_distribution_rules_path(tenant_id: @alfa.id)
    assert_selector "h1"
    assert_acessivel

    visit settings_operation_trails_path
    assert_selector "h1"
    assert_acessivel

    visit customer_path(@ana)
    assert_text "Recupera"
    assert_acessivel
  end

  test "o usuário de operação vê o nome da operação no cabeçalho, só o cliente distribuído e as pessoas da operação" do
    entrar @caio
    assert_selector "body > header", text: "Recupera"

    visit customers_path
    assert_selector "h1", text: "Clientes"
    assert_text "Ana Distribuída"
    assert_no_text "Bia da Equipe"
    assert_acessivel
    sem_rolagem_horizontal

    click_link "Ana Distribuída"
    assert_selector "h1", text: "Ana Distribuída"
    assert_acessivel

    visit customer_path(@bia)
    assert_no_text "Bia da Equipe"

    visit operation_people_path
    assert_selector "h1", text: "Pessoas da Recupera"
    assert_text "Caio"
    assert_acessivel
  end
end
