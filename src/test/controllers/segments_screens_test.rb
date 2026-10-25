require "test_helper"

# Telas de segmentos e de índices (08): aba Segmentos com conferência, aba Índices, "Buscar índices agora", lista e ficha de clientes com o segmento,
# permissões (R157, MT-3) e isolamento por credor (V10).
class SegmentsScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  def segment_params(**overrides) = { tenant_id: @alfa.id, segment: { name: "Varejo PF recente", min_overdue_days: "1", max_overdue_days: "90", max_balance_cents: "5.000,00", person_type: "person" }.merge(overrides) }

  test "R154: criar leva à conferência com 'Entram N contratos'; nada é gravado até confirmar; confirmar reclassifica e volta à lista" do
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    entrar(users(:joana))
    get new_settings_segment_path(tenant_id: @alfa.id)
    assert_response :success

    assert_no_difference "Segment.count" do
      post settings_segments_path, params: segment_params
      assert_response :success
    end
    assert_select "h1", "Conferir mudança nos segmentos"
    assert_select "p", text: /Entram 1 contrato \(R\$ 1\.200,00\) em Varejo PF recente: 1 vindos de Demais/
    assert_select "button", "Confirmar mudança nos segmentos"
    assert_select "a", "Voltar sem mudar"
    token = css_select("input[name='confirmation[token]']").first["value"]

    post settings_segment_confirmation_path, params: { tenant_id: @alfa.id, confirmation: { token: token } }
    assert_redirected_to settings_segments_path
    assert_equal [ "Varejo PF recente", 1 ], [ segment_of(contract), @alfa.segments.where(name: "Varejo PF recente").count ]
    follow_redirect!
    assert_select "td", text: /Atraso de 1 a 90 dias · Saldo até R\$ 5\.000,00 · Tipo: Pessoa física/
    assert_select "th", text: "Demais"
  end

  test "critérios impossíveis voltam ao formulário com a mensagem do campo e texto de número inválido" do
    entrar(users(:joana))
    post settings_segments_path, params: segment_params(min_overdue_days: "10", max_overdue_days: "5")
    assert_response :unprocessable_content
    assert_select "small[role=alert]", text: /não pode ser menor que o mínimo/
    post settings_segments_path, params: segment_params(max_balance_cents: "abc")
    assert_select "small[role=alert]", text: /informe o valor em reais/
    post settings_segments_path, params: segment_params(name: "Demais")
    assert_response :unprocessable_content
    assert_select "div", text: /já existe um segmento com esse nome/
  end

  test "R155: desativar, reativar e mover passam pela conferência; Demais não tem botões" do
    a = make_segment(@alfa, "A", min_overdue_days: 1)
    b = make_segment(@alfa, "B", min_overdue_days: 5)
    entrar(users(:joana))
    get settings_segments_path
    assert_select "tr#segmento-#{a.id} button", text: "Desativar"
    assert_select "tr#segmento-#{a.id} button", text: "Mover para baixo"
    assert_select "tr#segmento-#{a.id} button", text: "Mover para cima", count: 0
    assert_select "tr#segmento-#{b.id} button", text: "Mover para baixo", count: 0
    assert_select "tr#segmento-#{Segment.catch_all_of(@alfa).id} button", count: 0

    delete settings_segment_activation_path(a)
    assert_select "h1", "Conferir mudança nos segmentos"
    post settings_segment_movement_path(b), params: { movement: { direction: "up" } }
    assert_select "h1", "Conferir mudança nos segmentos"
    assert_equal true, a.reload.active, "nada gravado antes da confirmação"
    post settings_segment_activation_path(Segment.catch_all_of(@alfa))
    assert_response :not_found
  end

  test "R157 (critério de aceite): só com a 4 as telas abrem sem botões e o envio direto é recusado e registrado (MT-3)" do
    reader = make_user(@alfa, %w[change_settings])
    entrar(reader)
    make_segment(@alfa, "A", min_overdue_days: 1)
    get settings_segments_path
    assert_response :success
    assert_select "a", text: "Criar segmento", count: 0
    assert_select "button", text: "Desativar", count: 0
    assert_select "button", text: "Conferir mudança", count: 0

    assert_difference -> { AccessEvent.where(event: "access_denied", tenant_id: @alfa.id, user_id: reader.id).count }, 3 do
      post settings_segments_path, params: segment_params
      assert_response :not_found
      post settings_segment_confirmation_path, params: { tenant_id: @alfa.id, confirmation: { token: "x" } }
      assert_response :not_found
      patch settings_segment_policy_path, params: { tenant_id: @alfa.id, segment_policy: { value: "any_bill" } }
      assert_response :not_found
    end
    assert_equal 1, @alfa.segments.where.not(catch_all: true).count
  end

  test "MT-3 e V10: Marta com a 14 na Alfa e só consulta na Beta vê os segmentos só da Alfa; a Beta é recusada por link direto" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    beta_segment = make_segment(@beta, "Beta A", min_overdue_days: 1)
    entrar(marta)
    get settings_segments_path
    assert_select "h2", text: "Escola Alfa"
    assert_select "h2", text: "Clínica Beta", count: 0
    get edit_settings_segment_path(beta_segment)
    assert_response :not_found
    post settings_segments_path, params: segment_params.merge(tenant_id: @beta.id)
    assert_response :not_found
    patch settings_segment_policy_path, params: { tenant_id: @beta.id, segment_policy: { value: "any_bill" } }
    assert_response :not_found
    assert AccessEvent.exists?(event: "access_denied", tenant_id: @beta.id, user_id: marta.id)
  end

  test "R151: a política de produto passa pela conferência e o cartão aparece na aba" do
    entrar(users(:joana))
    get settings_segments_path
    assert_select "legend", "Produto do contrato no segmento"
    patch settings_segment_policy_path, params: { tenant_id: @alfa.id, segment_policy: { value: "any_bill" } }
    assert_select "h1", "Conferir mudança nos segmentos"
    assert_equal "most_overdue", @alfa.setting.reload.segment_product_policy
    patch settings_segment_policy_path, params: { tenant_id: @alfa.id, segment_policy: { value: "invalida" } }
    assert_response :unprocessable_content
  end

  test "R159 (critério de aceite): lista com coluna Segmento do contrato mais atrasado e filtro por qualquer contrato, inclusive sem segmento; ficha por contrato" do
    make_segment(@alfa, "Varejo PF recente", min_overdue_days: 61, max_overdue_days: 90)
    maria = customer_of(@alfa, FakeData.cpf(81), "Maria Souza")
    make_contract(@alfa, "101", bills: [ { overdue: 61, cents: 100_000 } ], customers: [ maria ])
    c102 = make_contract(@alfa, "102", bills: [ { overdue: 10, cents: 50_000 } ], customers: [ maria ])
    sem = make_contract(@alfa, "103", bills: [ { overdue: 5, cents: 50_000 } ], customers: [ maria ])
    sem.bills.update_all(status: "paid")
    recalc(@alfa)
    entrar(users(:joana))

    get customers_path(q: "Maria")
    assert_select "th", text: "Segmento"
    assert_select "tbody tr", count: 1
    assert_select "tbody td", text: "Varejo PF recente"
    varejo = Segment.find_by!(name: "Varejo PF recente")
    demais = Segment.catch_all_of(@alfa)
    [ varejo.id, demais.id, "none" ].each do |value|
      get customers_path(q: "Maria", segment: value)
      assert_select "tbody tr", count: 1, message: "filtro #{value}"
    end
    other = customer_of(@alfa, FakeData.cpf(82), "Outro Cliente")
    make_contract(@alfa, "201", bills: [ { overdue: 5 } ], customers: [ other ])
    recalc(@alfa)
    get customers_path(segment: "none")
    assert_select "tbody tr", count: 1, message: "só quem tem contrato sem segmento"
    get customers_path(segment: varejo.id)
    assert_select "tbody tr", count: 1

    get customer_path(maria)
    assert_select "td", text: "Varejo PF recente"
    assert_select "td", text: "Demais"
    assert_select "td", text: "Sem segmento"
    assert_select "#historico-de-segmento tbody tr", minimum: 2
    assert_equal "Demais", segment_of(c102)
  end

  test "V10 na lista: segmento de outro credor não filtra nem aparece" do
    other = make_segment(@beta, "Beta A", min_overdue_days: 1)
    make_contract(@beta, "B", bills: [ { overdue: 5 } ])
    recalc(@beta)
    entrar(users(:carlos))
    get customers_path
    assert_select "option", text: "Beta A", count: 0
    get customers_path(segment: other.id)
    assert_response :success
    assert_select "tbody tr", count: 0
  end
end
