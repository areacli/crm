require "test_helper"

# Telas dos acordos (11): simulação, proposta, ficha, aprovar, recusar, cancelar, aceite, termo, lista, pendentes, menu, configuração, filtro da cidade e V10.
class AgreementsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
  end

  teardown { travel_back }

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def form(overrides = {})
    { mode: "installments", bill_ids: [ @nf1.id, @nf2.id ], discounts: { fine: "50", interest: "50" }, down_payment: "343,66", down_payment_on: "2026-11-05", installments: "4", day: "5" }.merge(overrides)
  end

  # O aceite é registrado depois da montagem: o relógio parado do teste avança para o fim da tarde.
  def later! = travel_to(AGREEMENT_DAY.in_time_zone.change(hour: 16))

  def accept_params(overrides = {})
    { presented_channel: "whatsapp", presented_at: "2026-10-30T14:50", accepted_channel: "phone", accepted_at: "2026-10-30T15:10", proof: "88213", accepted_by_customer_id: @customer.id }.merge(overrides)
  end

  test "R211: a ficha oferece 'Simular acordo' a quem negocia, no credor do cliente, e não a quem só consulta" do
    entrar(users(:carlos))
    get customer_path(@customer)
    assert_select "a", text: "Simular acordo"

    delete session_path
    viewer = make_user(@alfa, [])
    entrar(viewer)
    get customer_path(@customer)
    assert_select "a", text: "Simular acordo", count: 0
    get new_customer_agreement_simulation_path(@customer)
    assert_response :not_found
    post customer_agreement_simulations_path(@customer), params: { agreement: form }
    assert_response :not_found
    assert_operator AccessEvent.where(event: "access_denied").count, :>=, 2
  end

  test "R212 a R214: a simulação mostra a base, os descontos, a entrada e a tabela de parcelas com os números da especificação" do
    entrar(users(:carlos))
    get new_customer_agreement_simulation_path(@customer)
    assert_response :success
    assert_select "input[type=checkbox][name='agreement[bill_ids][]']", 2

    post customer_agreement_simulations_path(@customer), params: { agreement: form }, headers: htmx
    assert_response :success
    assert_select "#simulacao tfoot td", text: "R$ 1.579,93"
    assert_select "#simulacao dd", text: "R$ 1.543,66"
    assert_select "#simulacao dd", text: "19,56%"
    assert_select "#simulacao dd", text: "R$ 1.590,19"
    assert_select "#simulacao td", text: "R$ 312,53"
    assert_select "#simulacao th", text: "Parcela 4"
    assert_select "#simulacao td", text: "07/12/2026"
    assert_select "#simulacao aside", text: /Dentro dos seus limites: a proposta nasce aprovada/
    assert_select "#simulacao aside", text: /Cidade não reconhecida: só feriados nacionais/
  end

  test "R215: a simulação que viola o teto mostra a mensagem do limite e a proposta não é criada" do
    entrar(users(:carlos))
    post customer_agreement_simulations_path(@customer), params: { agreement: form(discounts: { principal: "5" }) }, headers: htmx
    assert_select "#simulacao aside", text: /o segmento não permite desconto em principal/i

    post customer_agreements_path(@customer), params: { agreement: form(discounts: { principal: "5" }) }
    assert_response :unprocessable_content
    assert_includes response.body, "O segmento não permite desconto em principal."
    assert_select "input[name='agreement[down_payment]'][value='343,66']"
    assert_equal 0, Agreement.count
  end

  test "R216: fora dos limites a simulação avisa que a proposta nasce pendente" do
    entrar(users(:carlos))
    post customer_agreement_simulations_path(@customer), params: { agreement: form(discounts: { fine: "100", interest: "50" }) }, headers: htmx

    assert_select "#simulacao aside", text: /nasce pendente de aprovação/
  end

  test "campo inválido do formulário volta com a mensagem junto do campo" do
    entrar(users(:carlos))
    post customer_agreement_simulations_path(@customer), params: { agreement: form(discounts: { fine: "abc" }) }, headers: htmx
    assert_select "aside", text: /Informe o desconto em percentual/
    post customer_agreement_simulations_path(@customer), params: { agreement: form(down_payment: "abc") }
    assert_select "small[data-erro]", text: /Valor da entrada/
    post customer_agreement_simulations_path(@customer), params: { agreement: form(bill_ids: []) }
    assert_select "aside", text: /Escolha os títulos do acordo/
  end

  test "R211, R241: cria a proposta pela tela, a ficha mostra 'proposta aguardando aceite' e o título preso, e a página do acordo abre" do
    entrar(users(:carlos))
    post customer_agreements_path(@customer), params: { agreement: form }
    agreement = Agreement.sole
    assert_redirected_to agreement_path(agreement)
    follow_redirect!
    assert_select "h1", text: /Acordo ACD-000001/
    assert_select "h1 .situacao", text: "Aprovada"
    assert_select "dd", text: "R$ 1.543,66"
    assert_select "table th", text: "Parcela 4"
    assert_select "button", text: "Aprovar proposta", count: 0

    get customer_path(@customer)
    assert_select "ul.promessas li", text: /1 proposta aguardando aceite/
    assert_select "ul.promessas a", text: "ACD-000001"
    assert_select "small", text: /Em proposta ACD-000001/
    assert_select "#historico-de-acordos"
    assert_select "td", text: "Proposta montada"
  end

  test "R216, R204: a pendente aparece em 'Acordos pendentes' só para quem a pode aprovar; o gestor aprova, e o operador que a montou não aprova por link direto" do
    entrar(users(:carlos))
    post customer_agreements_path(@customer), params: { agreement: form(discounts: { fine: "100", interest: "50" }) }
    agreement = Agreement.sole
    assert_predicate agreement, :state_pending?
    get agreement_path(agreement)
    assert_select "aside", text: /passou dos limites de quem a montou/
    assert_select "button", text: "Aprovar proposta", count: 0
    get pending_agreements_path
    assert_select "td", text: "Nenhuma", count: 0
    assert_select ".vazio", text: "Nenhuma proposta pendente para você aprovar."
    assert_difference -> { AccessEvent.where(event: "access_denied").count }, 1 do
      post agreement_approval_path(agreement)
    end
    assert_response :not_found

    delete session_path
    entrar(users(:joana))
    get root_path
    assert_select "nav a", text: "Acordos pendentes (1)"
    get pending_agreements_path
    assert_select "tbody tr", 1
    assert_select "tbody td", text: "R$ #{Money.format(agreement.value_cents)}"
    post agreement_approval_path(agreement)
    assert_redirected_to agreement_path(agreement)
    assert_predicate agreement.reload, :state_approved?
    assert_equal users(:joana), agreement.decided_by
  end

  test "R216: o gestor recusa com motivo; sem motivo a recusa volta com a mensagem" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 10_000, "interest" => 5_000 })
    entrar(users(:joana))
    post agreement_refusal_path(agreement), params: { agreement: { reason: " " } }
    assert_redirected_to agreement_path(agreement)
    assert_equal I18n.t("agreements.refused.reason_required"), flash[:alert]
    assert_predicate agreement.reload, :state_pending?

    post agreement_refusal_path(agreement), params: { agreement: { reason: "Desconto alto demais" } }, headers: { "HTTP_REFERER" => agreement_url(agreement) }
    assert_predicate agreement.reload, :state_refused?
    get agreement_path(agreement)
    assert_select "aside", text: /Motivo: Desconto alto demais/
  end

  test "R218: qualquer operador com a 16 cancela a proposta, com motivo; quem não tem a 16 não vê nem cancela" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ])
    entrar(users(:ana))
    get agreement_path(agreement)
    assert_select "summary", text: "Cancelar proposta"
    post agreement_cancellation_path(agreement), params: { agreement: { reason: "Cliente desistiu" } }, headers: { "HTTP_REFERER" => agreement_url(agreement) }
    assert_predicate agreement.reload, :state_canceled?
    assert_empty AgreementBill.where(held: true)

    other = create_proposal(@customer, [ @nf1 ])
    delete session_path
    entrar(make_user(@alfa, []))
    post agreement_cancellation_path(other), params: { agreement: { reason: "x" } }
    assert_response :not_found
    assert_predicate other.reload, :state_approved?
  end

  test "R219, R220: o termo abre para imprimir, o aceite é registrado pela tela e o termo guardado aparece" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ])
    later!
    entrar(users(:carlos))
    get agreement_term_path(agreement)
    assert_response :success
    assert_select "h1", text: "Termo de acordo ACD-000001"
    assert_select "td", text: "R$ 343,66"
    assert_select "p", text: /taxa efetiva anual de 19,56%/
    assert_select "p strong", text: "Soma total a pagar: R$ 1.590,19."
    assert_select "main", text: /Escola Alfa Ltda/
    assert_select "button[onclick]", 0

    get agreement_path(agreement)
    assert_select "h2", text: "Registrar o aceite"
    assert_select "select[name='acceptance[accepted_by_customer_id]'] option", text: "Maria Souza, responsável financeiro"
    post agreement_acceptance_path(agreement), params: { acceptance: accept_params }
    assert_redirected_to agreement_path(agreement)
    assert_predicate agreement.reload, :state_awaiting_effectuation?
    follow_redirect!
    assert_select "h2", text: "Aceite registrado"
    assert_select "dd", text: /Maria Souza, responsável financeiro/
    assert_select "h2", text: "Registrar o aceite", count: 0

    get customer_path(@customer)
    assert_select "ul.promessas li", text: /ACD-000001.*NF-1 e NF-2.*aguardando efetivação|Aguardando efetivação/mi
  end

  test "R220: o aceite recusado volta à página com a mensagem e nada muda" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ])
    @nf1.update!(amount_cents: 90_000)
    later!
    entrar(users(:carlos))
    post agreement_acceptance_path(agreement), params: { acceptance: accept_params }
    assert_redirected_to agreement_path(agreement)
    follow_redirect!
    assert_select "aside", text: /O valor do título NF-1 mudou\. Monte a proposta de novo\./
    assert_predicate agreement.reload, :state_approved?
  end

  test "R219: o termo da pendente e o de credor sem CNPJ não abrem" do
    pending = create_proposal(@customer, [ @nf1 ], discounts: { "fine" => 10_000 })
    entrar(users(:carlos))
    get agreement_term_path(pending)
    assert_redirected_to agreement_path(pending)
    assert_equal I18n.t("agreements.terms.show.not_ready"), flash[:alert]
  end

  test "R243: a lista de acordos tem filtros de situação, período e operador, paginação e os casos do gestor só para quem tem a 17" do
    approved = create_proposal(@customer, [ @nf1 ])
    pending = create_proposal(@customer, [ @nf2 ], user: users(:ana), discounts: { "fine" => 10_000 }, installments: 2, down: 20_000)
    entrar(users(:ana))
    get agreements_path
    assert_response :success
    assert_select "tbody tr", 2
    assert_select "#casos", 0
    assert_select "th", text: "Credor", count: 0

    get agreements_path(state: "pending")
    assert_select "tbody tr", 1
    assert_select "tbody a", text: pending.number
    get agreements_path(user: users(:carlos).id)
    assert_select "tbody a", text: approved.number
    assert_select "tbody tr", 1
    get agreements_path(from: "2026-11-01")
    assert_select ".vazio", text: "Nenhuma proposta ou acordo com estes filtros."

    delete session_path
    Agreement.where(id: pending.id).update_all(user_id: users(:carlos).id)
    entrar(users(:joana))
    get agreements_path
    assert_select "#casos tbody th", text: "Pendente que ninguém pode aprovar", count: 0
  end

  test "R243, R245a: o caso 'pendente que ninguém pode aprovar' aparece para o gestor com a 17 e a lista mostra só os credores da permissão" do
    # Só Joana (Gestora) e Carlos (Operador) atuam na Alfa; se Joana montou a pendente, ninguém mais a cobre.
    create_proposal(@customer, [ @nf2 ], user: users(:joana), discounts: { "fine" => 10_000 }, installments: 2, down: 20_000)
    Agreement.update_all(state: "pending")
    entrar(users(:joana))
    get agreements_path
    assert_select "#casos tbody th", text: "Pendente que ninguém pode aprovar"
  end

  test "R245a, V10: a lista e a página de acordo de outro credor não aparecem para quem não tem a 16 nele" do
    Segment.catch_all_of(@beta).update!(**AgreementsTestHelper::EXAMPLE_VARIABLES)
    rebuild_agreement_limits(@beta)
    beta_customer, beta_nf = promise_scenario(@beta, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João Souza").then { |customer, bill, _| [ customer, bill ] }
    @beta.update!(cnpj: "45723174000110", legal_name: "Clínica Beta Ltda")
    beta_agreement = create_proposal(beta_customer, [ beta_nf ], user: users(:marta))
    alfa_agreement = create_proposal(@customer, [ @nf1 ])

    entrar(users(:carlos))
    get agreements_path
    assert_select "tbody tr", 1
    assert_select "tbody a", text: alfa_agreement.number
    assert_difference -> { AccessEvent.where(event: "access_denied").count }, 1 do
      get agreement_path(beta_agreement)
    end
    assert_response :not_found
    post agreement_acceptance_path(beta_agreement), params: { acceptance: accept_params }
    assert_response :not_found
    get agreement_term_path(beta_agreement)
    assert_response :not_found
    get new_customer_agreement_simulation_path(beta_customer)
    assert_response :not_found

    delete session_path
    entrar(users(:ana))
    get agreements_path
    assert_select "th", text: "Credor"
    assert_select "tbody tr", 2
    get agreements_path(tenant: @beta.id)
    assert_select "tbody tr", 1
  end

  test "P1: o grupo Cobrança do menu traz Acordos e Promessas pendentes; o Operador padrão negocia acordos" do
    entrar(users(:carlos))
    get root_path
    assert_select "nav h2", text: "Cobrança"
    assert_select "nav a", text: "Acordos"
    assert_select "nav h2", text: "Administração", count: 0
    assert_includes Permission::OPERATOR, "negotiate_agreements"

    delete session_path
    viewer = make_user(@alfa, [])
    entrar(viewer)
    get root_path
    assert_select "nav h2", text: "Cobrança", count: 0
    get agreements_path
    assert_response :not_found
  end

  test "R249, AB9: o filtro 'cidade não reconhecida' da lista de clientes e o aviso da ficha para quem edita o cadastro" do
    Municipality.create!(ibge_code: "3550308", name: "São Paulo", state: "SP")
    other = make_bill(@alfa, number: "NF-7", amount_cents: 10_000, document: PaymentsHelper::JOAO, contract_code: "CT-7", due: ChargesTestHelper::DUE, name: "João Souza").customer
    other.contacts.create!(tenant: @alfa, kind: "address", key: "a1", value: "Rua A, 1", city: "São Paulo", state: "SP", origin: "screen")
    entrar(users(:joana))
    get customers_path(unrecognized_city: "1")
    assert_select "tbody a", text: "Maria Souza"
    assert_select "tbody a", text: "João Souza", count: 0

    get customer_path(@customer)
    assert_select "aside", text: /Cidade não reconhecida: o endereço deste cliente não casa/
    get customer_path(other)
    assert_select "aside", text: /Cidade não reconhecida/, count: 0

    delete session_path
    entrar(make_user(@alfa, []))
    get customer_path(@customer)
    assert_select "aside", text: /Cidade não reconhecida: o endereço deste cliente/, count: 0
  end

  test "R246, T6: a aba 'Promessas e acordos' tem as políticas, as variáveis e os limites, só com a 14, e grava com registro" do
    entrar(users(:carlos))
    get settings_promises_path
    assert_response :not_found

    delete session_path
    entrar(users(:joana))
    get settings_promises_path
    assert_response :success
    assert_select "h1", text: "Promessas e acordos"
    assert_select "nav.abas a", text: "Promessas e acordos"
    assert_select "h2", text: /Políticas dos acordos/
    assert_select "h2", text: /Variáveis de acordo dos segmentos/
    assert_select "h2", text: /Limites de acordo por perfil/
    assert_select "legend", text: "Tolerância de valor dos títulos de acordo"
    assert_select "legend", text: "Mínimo para quebrar e efetivar"

    patch settings_agreement_policies_path, params: { tenant_id: @alfa.id, tab: "agreements", policies: { break_form: "single_title", tolerance_agreement: { kind: "cents", value: "2,00" } } }
    assert_redirected_to settings_promises_path
    assert_equal "single_title", Agreements::Policies.value(@alfa.setting.reload, "break_form")
    follow_redirect!
    assert_select "summary", text: "Ver histórico"

    patch settings_agreement_variables_path, params: { tenant_id: @alfa.id, segments: { Segment.catch_all_of(@alfa).id => { max_installments: "8", min_installment: "100,00", min_down_payment_pct: "10",
                                                                                                                        down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30" } } }
    assert_equal 8, Segment.catch_all_of(@alfa).reload.agreement_max_installments

    patch settings_agreement_limits_path, params: { tenant_id: @alfa.id, limits: { Segment.catch_all_of(@alfa).id => { profiles(:alfa_operator).id => { max_installments: "3", min_down_payment_pct: "20" } } } }
    assert_equal 3, AgreementLimit.find_by!(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_operator)).max_installments
    follow_redirect!
    assert_select "td", text: /Acordos: Tolerância de valor dos títulos de acordo|Acordos, Demais/
  end

  test "R246: parâmetros do acordo na aba 'Segmentos e encargos' e crédito e tolerância na aba 'Pagamentos'" do
    entrar(users(:joana))
    get settings_segments_path
    assert_select "legend", text: "Parâmetros dos acordos do credor"
    patch settings_agreement_parameters_path, params: { tenant_id: @alfa.id, credor: { installment_rate_pct: "2", installment_method: "sac", agreement_days_convention: "thirty", agreement_fine_base: "corrected" },
                                                        segments: { Segment.catch_all_of(@alfa).id => { installment_rate_pct: "", installment_method: "", agreement_days_convention: "", agreement_fine_base: "" } } }
    assert_redirected_to settings_segments_path
    assert_equal "sac", @alfa.setting.reload.installment_method

    patch settings_agreement_parameters_path, params: { tenant_id: @alfa.id, credor: { installment_rate_pct: "999", installment_method: "sac", agreement_days_convention: "thirty", agreement_fine_base: "corrected" } }
    assert_redirected_to settings_segments_path
    assert_equal I18n.t("agreements.settings.invalid_params"), flash[:alert]

    get settings_payment_policy_path
    assert_select "legend", text: "Tolerância de valor do pagamento direto de título"
    assert_select "legend", text: "Uso do crédito do contrato"
    patch settings_agreement_policies_path, params: { tenant_id: @alfa.id, tab: "payments", policies: { tolerance_direct: { kind: "cents", value: "0,50" }, credit_use: "record_only" } }
    assert_redirected_to settings_payment_policy_path
    assert_equal 50, Agreements::Policies.tolerance_cents(@alfa.setting.reload, "direct", 100_000)
  end

  test "R246, A7: quem tem só a permissão 4 não vê os parâmetros dos acordos nem grava" do
    manager_without_policies = make_user(@alfa, [ "change_settings" ])
    entrar(manager_without_policies)
    get settings_segments_path
    assert_select "legend", text: "Parâmetros dos acordos do credor", count: 0
    patch settings_agreement_parameters_path, params: { tenant_id: @alfa.id, credor: { installment_rate_pct: "2", installment_method: "sac", agreement_days_convention: "thirty", agreement_fine_base: "corrected" } }
    assert_response :not_found
    assert_equal BigDecimal("1.5"), @alfa.setting.reload.installment_rate_pct
  end

  test "R246, V10: quem tem a 14 só na Alfa não vê nem altera a configuração de acordos da Beta; o envio direto é recusado e registrado" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    entrar(marta)
    get settings_promises_path
    assert_select "h2", text: /Políticas dos acordos — #{@alfa.name}/
    assert_select "h2", text: /Políticas dos acordos — #{@beta.name}/, count: 0

    [ settings_agreement_policies_path, settings_agreement_variables_path, settings_agreement_limits_path, settings_agreement_parameters_path ].each do |path|
      assert_difference -> { AccessEvent.where(event: "access_denied").count }, 1 do
        patch path, params: { tenant_id: @beta.id, policies: { break_form: "single_title" } }
      end
      assert_response :not_found
    end
    assert_equal({}, @beta.setting.reload.agreement_policies)
  end

  test "AC7: o perfil com 'administrar acordos' e sem 'negociar acordos' é recusado" do
    profile = Profile.new(tenant: @alfa, name: "Sem negociar", permissions: %w[view_portfolio administer_agreements])

    assert_not profile.valid?
    assert profile.errors.added?(:permissions, :needs_negotiate_agreements)
  end

  test "R183 (10): o título em proposta aparece bloqueado no bloco da promessa do acionamento" do
    create_proposal(@customer, [ @nf1 ])
    entrar(users(:joana))
    get new_customer_contact_attempt_path(@customer), headers: htmx,
        params: { contact_attempt: { result_id: result_of(@alfa, :promised).id, promise_contract_id: @nf1.contract_id, promise_on: (AGREEMENT_DAY + 3).iso8601 } }
    assert_response :success
    assert_includes response.body, "em proposta ou acordo ACD-000001"
  end
end
