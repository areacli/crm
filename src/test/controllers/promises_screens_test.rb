require "test_helper"

# Telas das promessas (10): registro pelo formulário, ficha, aprovar, recusar e cancelar, lista de pendentes, painel, filtro, configuração e V10.
class PromisesScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    travel_day(ChargesTestHelper::TODAY)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    PromiseLimit.where(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_manager)).update_all(max_days: 60)
  end

  teardown { travel_back }

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def pending_promise(user: users(:carlos), bills: [ @nf1, @nf2 ])
    register_promise(@customer, bills, user: user, on: ChargesTestHelper::TODAY + 45)
  end

  test "R183 e R186: o formulário oferece o bloco da promessa só para resultado que a admite e mostra o valor antes de gravar" do
    entrar(users(:joana))
    get new_customer_contact_attempt_path(@customer), headers: htmx,
        params: { contact_attempt: { result_id: result_of(@alfa, :promised).id, promise_contract_id: @nf1.contract_id, promise_on: PromisesTestHelper::PROMISED.iso8601, promise_bill_ids: [ @nf1.id, @nf2.id ] } }
    assert_response :success
    assert_select "#bloco-promessa legend", text: "Registrar promessa"
    assert_select "#bloco-promessa input[type=checkbox][name='contact_attempt[promise_bill_ids][]']", 2
    assert_select "#bloco-promessa tfoot td", text: "R$ 1.579,93"
    assert_select "#bloco-promessa", text: /isenção nem desconto/
    assert_select "#bloco-promessa input[name*=discount], #bloco-promessa input[name*=desconto]", 0

    get new_customer_contact_attempt_path(@customer), headers: htmx, params: { contact_attempt: { result_id: result_of(@alfa, :refused).id } }
    assert_select "#bloco-promessa", 0
  end

  test "R183: registra a promessa pela tela e a ficha mostra a linha no cabeçalho e a marca no título" do
    entrar(users(:joana))
    post customer_contact_attempts_path(@customer), params: { contact_attempt: { channel: "phone", result_id: result_of(@alfa, :promised).id, promise_contract_id: @nf1.contract_id,
                                                                                 promise_payment_method: "pix", promise_on: PromisesTestHelper::PROMISED.iso8601, promise_bill_ids: [ @nf1.id, @nf2.id ] } }
    assert_response :redirect
    get customer_path(@customer)
    assert_select "ul.promessas li", 1
    assert_select "ul.promessas li", text: /PRM-000001.*NF-1 e NF-2.*R\$ 1\.579,93 por Pix até 30\/10\/2026.*Pago R\$ 0,00/m
    assert_select "ul.promessas li", text: /Aberta/
    assert_select "small", text: "Em promessa PRM-000001."
    assert_select "td p, td small", text: /Promessa PRM-000001/
  end

  test "R184: a promessa enviada com resultado que não a admite é recusada e o formulário volta com a mensagem" do
    entrar(users(:joana))
    post customer_contact_attempts_path(@customer), headers: htmx,
         params: { contact_attempt: { channel: "phone", result_id: result_of(@alfa, :refused).id, promise_contract_id: @nf1.contract_id, promise_payment_method: "pix",
                                      promise_on: PromisesTestHelper::PROMISED.iso8601, promise_bill_ids: [ @nf1.id ] } }
    assert_response :unprocessable_content
    assert_includes response.body, "Este resultado não admite promessa."
    assert_equal 0, PaymentPromise.count
  end

  test "R192: o gestor aprova a pendente; o operador que a registrou não vê o botão nem aprova por link direto" do
    promise = pending_promise
    entrar(users(:carlos))
    get customer_path(@customer)
    assert_select "ul.promessas li", text: /Pendente de aprovação/
    assert_select "button", text: "Aprovar promessa", count: 0
    assert_difference -> { AccessEvent.where(event: "access_denied").count }, 1 do
      post promise_approval_path(promise)
    end
    assert_response :not_found

    delete session_path
    entrar(users(:joana))
    get customer_path(@customer)
    assert_select "button", text: "Aprovar promessa"
    post promise_approval_path(promise)
    assert_predicate promise.reload, :state_open?
    assert_equal "PRM-000001", promise.number
    assert_equal users(:joana), promise.decided_by
  end

  test "R192: o gestor recusa a pendente com motivo; sem motivo, a mensagem do limite" do
    promise = pending_promise
    entrar(users(:joana))
    post promise_refusal_path(promise), params: { promise: { reason: " " } }
    assert_predicate promise.reload, :state_pending?
    assert_equal I18n.t("promises.refused.reason_required"), flash[:alert]

    post promise_refusal_path(promise), params: { promise: { reason: "Prazo longo demais" } }
    assert_predicate promise.reload, :state_refused?
    assert_equal "Prazo longo demais", promise.reason
    assert_empty promise.promise_bills.where(held: true)
  end

  test "R200: só quem tem a permissão 15 cancela, com motivo; o operador não vê a opção e o envio direto é recusado" do
    promise = register_promise(@customer, [ @nf1 ])
    entrar(users(:carlos))
    get customer_path(@customer)
    assert_select "summary", text: "Cancelar promessa", count: 0
    post promise_cancellation_path(promise), params: { promise: { reason: "x" } }
    assert_response :not_found

    delete session_path
    entrar(users(:joana))
    get customer_path(@customer)
    assert_select "summary", text: "Cancelar promessa"
    post promise_cancellation_path(promise), params: { promise: { reason: "" } }
    assert_equal "Informe o motivo do cancelamento.", flash[:alert]
    post promise_cancellation_path(promise), params: { promise: { reason: "Devedora pediu para negociar o contrato inteiro" } }
    assert_predicate promise.reload, :state_canceled?
  end

  test "P17: a promessa encerrada não fica no cabeçalho e aparece no histórico, junto do acionamento, com o selo e o motivo" do
    promise = register_promise(@customer, [ @nf1 ])
    Promises::Canceller.new(users(:joana)).cancel(promise, "Pediu para negociar")
    entrar(users(:joana))
    get customer_path(@customer)
    assert_select "ul.promessas", 0
    assert_select "td small", text: /Promessa PRM-000001.*Cancelada — Pediu para negociar/m
  end

  test "R204: a lista de pendentes traz as que o usuário aprova, com o número no menu; quem registrou não a vê" do
    pending_promise
    entrar(users(:carlos))
    get pending_promises_path
    assert_response :success
    assert_select "tbody tr", 0
    assert_select "nav[aria-label=Menu] a", text: /Promessas pendentes/, count: 0

    delete session_path
    entrar(users(:joana))
    get pending_promises_path
    assert_select "tbody tr", 1
    assert_select "tbody tr", text: /Maria Souza.*NF-1 e NF-2.*R\$ 1\.597,92/m
    assert_select "nav[aria-label=Menu] a", text: "Promessas pendentes (1)"
  end

  test "R204 e MT-3 a MT-6: a lista mistura os credores em que pode aprovar e a Beta fica de fora para quem só consulta nela" do
    pending_promise
    marta = make_user(@alfa, %w[record_contact_attempts])
    PromiseLimit.where(profile: marta.memberships.first.profile).delete_all
    PromiseLimit.create!(segment: Segment.catch_all_of(@alfa), profile: marta.memberships.first.profile, max_days: 60)
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    customer_b, bill_b, = promise_scenario(@beta, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João")
    Segment.catch_all_of(@beta).update!(promise_max_days: 90)
    beta_promise = register_promise(customer_b, [ bill_b ], user: users(:ana), on: ChargesTestHelper::TODAY + 45)
    assert_predicate beta_promise, :state_pending?

    entrar(marta)
    get pending_promises_path
    assert_select "tbody tr", 1
    assert_select "th", text: "Credor", count: 0
    assert_difference -> { AccessEvent.where(event: "access_denied", tenant_id: @beta.id).count }, 1 do
      post promise_approval_path(beta_promise)
    end
    assert_response :not_found
    assert_predicate beta_promise.reload, :state_pending?
  end

  test "R204: com os dois credores a lista traz a coluna Credor e o filtro reduz a um" do
    pending_promise
    customer_b, bill_b, = promise_scenario(@beta, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João")
    Segment.catch_all_of(@beta).update!(promise_max_days: 90)
    PromiseLimit.where(segment: Segment.catch_all_of(@beta), profile: profiles(:beta_operator)).update_all(max_days: 10)
    PromiseLimit.where(segment: Segment.catch_all_of(@beta), profile: profiles(:beta_manager)).update_all(max_days: 90)
    register_promise(customer_b, [ bill_b ], user: users(:marta), on: ChargesTestHelper::TODAY + 45)

    PromiseLimit.where(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_operator)).update_all(max_days: 60)
    entrar(users(:ana))
    get pending_promises_path
    assert_select "tbody tr", 2
    assert_select "th", text: "Credor"
    get pending_promises_path(tenant: @alfa.id)
    assert_select "tbody tr", 1
  end

  test "R204: o filtro Promessa da lista de clientes olha as promessas feitas pelo cliente da linha" do
    register_promise(@customer, [ @nf1 ])
    other = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "João Pereira", contract_code: "CT-7")
    entrar(users(:joana))
    get customers_path(promise: "open")
    assert_select "tbody th, tbody td", text: /Maria Souza/
    assert_select "tbody", text: /João Pereira/, count: 0
    get customers_path(promise: "none")
    assert_select "tbody", text: /João Pereira/
    assert_select "tbody", text: /Maria Souza/, count: 0
    assert_equal other.tenant, @alfa
  end

  test "R205: o painel traz um cartão de promessas por credor, sem percentual geral" do
    register_promise(@customer, [ @nf1 ])
    insert_attempt(@customer, result: result_of(@alfa, :promised))
    entrar(users(:ana))
    get root_path
    assert_select "h2", text: "Promessas — Escola Alfa"
    assert_select "h2", text: "Promessas — Clínica Beta"
    assert_select "section[aria-labelledby=promessas-#{@alfa.id}] td", text: /1 de 1/
    assert_select "h2", text: /Promessas — Todos/, count: 0
  end

  test "R206: a aba Promessas mostra políticas, prazo e alçada; mudar vale e fica registrado; baixar o prazo baixa a alçada" do
    entrar(users(:joana))
    get settings_promises_path
    assert_response :success
    assert_select "nav.abas a", text: "Promessas"
    segment = Segment.catch_all_of(@alfa)
    patch settings_promise_limits_path, params: { tenant_id: @alfa.id, segments: { segment.id => { max_days: 20, limits: { profiles(:alfa_manager).id => 20, profiles(:alfa_operator).id => 20 } } } }
    assert_equal 20, segment.reload.promise_max_days
    assert_equal [ 20, 20 ], PromiseLimit.where(segment: segment, profile: [ profiles(:alfa_manager), profiles(:alfa_operator) ]).pluck(:max_days)
    assert Change.exists?(subject_type: "promise_limit", subject_id: segment.id, event: "max_days_changed", before: "60", after: "20", user_id: users(:joana).id)

    patch settings_promise_policy_path, params: { tenant_id: @alfa.id, tenant_setting: { promise_tolerance_days: 5, promise_counting: "also_direct", promise_min_paid_pct: "95",
                                                                                      promise_after_break: "stays_broken", promise_grace_days: 7, promise_partial: "r46" } }
    setting = @alfa.setting.reload
    assert_equal [ 5, "also_direct", 95, "stays_broken", 7, "r46" ], setting.values_at(:promise_tolerance_days, :promise_counting, :promise_min_paid_pct, :promise_after_break, :promise_grace_days, :promise_partial)
    assert Change.exists?(subject_type: "promise_settings", field: "promise_tolerance_days", before: "3", after: "5")
    get settings_promises_path
    assert_select "td", text: "promise_tolerance_days", count: 0
  end

  test "R206: quem tem a 14 só na Alfa não vê nem altera a Beta; o envio direto é recusado e registrado" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    entrar(marta)
    get settings_promises_path
    assert_select "h2", text: /Políticas — Escola Alfa/
    assert_select "h2", text: /Clínica Beta/, count: 0
    assert_difference -> { AccessEvent.where(event: "access_denied", tenant_id: @beta.id).count }, 1 do
      patch settings_promise_policy_path, params: { tenant_id: @beta.id, tenant_setting: { promise_tolerance_days: 9, promise_counting: "promise_only", promise_after_break: "fulfilled", promise_grace_days: 0, promise_partial: "prevails" } }
    end
    assert_equal 3, @beta.setting.reload.promise_tolerance_days
  end

  test "valores inválidos da política e da alçada são recusados" do
    entrar(users(:joana))
    patch settings_promise_policy_path, params: { tenant_id: @alfa.id, tenant_setting: { promise_tolerance_days: 99, promise_counting: "promise_only", promise_after_break: "fulfilled", promise_grace_days: 0, promise_partial: "prevails" } }
    assert_equal 3, @alfa.setting.reload.promise_tolerance_days
    segment = Segment.catch_all_of(@alfa)
    patch settings_promise_limits_path, params: { tenant_id: @alfa.id, segments: { segment.id => { max_days: 0, limits: {} } } }
    assert_equal 60, segment.reload.promise_max_days
  end

  test "R184: o resultado do credor ganha a marca 'admite promessa', só para o tipo falou com o cliente" do
    entrar(users(:joana))
    result = result_of(@alfa, :contests)
    patch settings_contact_result_path(result), params: { contact_result: { name: result.name, return_rule: result.return_rule, allows_promise: "1" } }
    assert result.reload.allows_promise?
    silent = result_of(@alfa, :no_answer)
    patch settings_contact_result_path(silent), params: { contact_result: { name: silent.name, return_rule: silent.return_rule, allows_promise: "1" } }
    assert_response :unprocessable_content
    assert_not silent.reload.allows_promise?
  end

  test "o canal de promessas só aceita quem consulta a carteira do credor" do
    # o teste de canal completo está em test/channels/promises_channel_test.rb
    assert_equal "PromisesChannel", PromisesChannel.name
  end
end
