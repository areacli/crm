require "test_helper"

# Etapa 4 de Operações (14, R315, R318 a R321, R324): posse no pagamento, políticas, origem nas listas, acionamento de outra origem sem texto,
# trilha e o cabeçalho da operação.
class OperationsStage4Test < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    @caio = make_operation_user(@operation, @alfa)
    @ana = make_customer(@alfa, document: FakeData.cpf(601), name: "Ana Quatro", contract_code: "Q-1")
    @contract = Contract.find_by!(code: "Q-1")
    Distribution.create!(tenant: @alfa, operation: @operation, contract: @contract, exposure: "all", starts_on: Date.current - 5)
    Operations::ReachBuilder.new(@alfa).rebuild
  end

  test "R321: o pagamento aplicado grava a posse do contrato na data" do
    payment = Payment.create!(tenant: @alfa, channel: make_channel(@alfa), bill: @ana.bills.first, bill_number: @ana.bills.first.number, paid_on: Date.current,
                              amount_cents: 1_000, applied_cents: 1_000, payment_method: "pix", status: "applied", identifier: "POSSE-1", document: @ana.document)
    assert_equal [ @operation.id ], payment.possession_operation_ids
  end

  test "R319: o gestor muda as políticas das operações, com registro" do
    sign_in_as users(:joana)
    patch settings_operation_policies_url(credor: @alfa.id), params: { policies: { operation_exclusive: "false", operation_default_exposure: "all", operation_exposure_business_days: "5",
                                                                                      operation_sees_other_deals: "true", operation_other_contact_attempts: "hidden", operation_manager_links: "true" } }
    setting = @alfa.setting.reload
    assert_equal [ false, "all", 5, true, "hidden", true ], [ setting.operation_exclusive, setting.operation_default_exposure, setting.operation_exposure_business_days,
                                                             setting.operation_sees_other_deals, setting.operation_other_contact_attempts, setting.operation_manager_links ]
    assert Change.exists?(subject_type: "tenant_setting", field: "operation_exclusive")
  end

  test "R318 e R315: a lista de acionamentos da equipe tem a origem; a operação vê o da equipe sem texto e sem autor" do
    attempt = record_attempt(@ana, users(:joana), text: "Texto sigiloso da equipe", contract_id: @contract.id)
    sign_in_as users(:joana)
    get contact_attempts_url, headers: TRECHO
    assert_select "th", text: "Origem"
    assert_select "td", text: "Equipe do credor"
    delete session_url

    sign_in_as @caio
    get_ficha(@ana, aba: "acionamentos")
    assert_response :success
    assert_not_includes response.body, "Texto sigiloso da equipe"
    assert_includes response.body, "Outra origem"
    assert attempt
  end

  test "R320: ficha aberta e busca do usuário de operação ficam na trilha; o gestor consulta" do
    sign_in_as @caio
    # A ficha chega em dois pedidos (a ficha e a aba interna); só o primeiro fica na trilha.
    get_ficha(@ana)
    get_clientes(busca: "Ana")
    get_ficha(make_customer(@alfa, document: FakeData.cpf(602), name: "Fora", contract_code: "Q-2"))
    kinds = OperationTrailEvent.where(user: @caio).order(:id).pluck(:kind)
    assert_equal %w[record_opened search not_found], kinds
    delete session_url

    sign_in_as users(:joana)
    get settings_operation_trails_url, headers: TRECHO
    assert_response :success
    assert_includes response.body, "Abriu a ficha"
  end

  test "R324: o cabeçalho mostra a operação do usuário (a casca a lê do menu)" do
    sign_in_as @caio
    get menu_path(format: :json)
    assert_equal "Recupera", response.parsed_body.dig("usuario", "operacao")
    get root_path
    assert_select "#operacao-atual[hidden]" # preenchido pela casca
  end
end
