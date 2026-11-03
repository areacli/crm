require "test_helper"

# Telas da etapa 1 de Operações (14, R306 a R310a, R325, R327): credenciar, ficha do credenciamento, situação, vínculos, pessoas da operação e o
# aviso de credenciamento suspenso na entrada.
class OperationsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  def entrar(user, password = "senha-de-teste-1") = post(session_path, params: { email_address: user.email_address, password: password })

  test "R306 e R325: o gestor do credor credencia pelo CNPJ e vê a senha temporária do gestor da operação uma vez" do
    sign_in_as users(:joana)
    get settings_operations_url
    assert_response :success
    assert_select "#menu-principal details.submenu[open] a[aria-current=page]", text: "Credenciadas"
    post settings_operations_url, params: { operation: { tenant_id: @alfa.id, cnpj: "11.444.777/0001-61", legal_name: "Recupera Cobranças Ltda", short_name: "Recupera",
                                                          manager_name: "Lia", manager_email: "lia@recupera.com.br" } }
    accreditation = Accreditation.last
    assert_redirected_to settings_operation_url(accreditation)
    follow_redirect!
    assert_select "h1", text: "Recupera"
    assert_includes response.body, "Senha temporária de lia@recupera.com.br"
    get settings_operation_url(accreditation)
    assert_not_includes response.body, "Senha temporária"
  end

  test "sem a permissão 18, Operações não aparece e o endereço é recusado" do
    sign_in_as users(:carlos)
    get root_url
    assert_select "#menu-principal .submenu a", text: "Credenciadas", count: 0
    get settings_operations_url
    assert_response :not_found
  end

  test "R307: suspender pede motivo e tira o acesso; a entrada avisa e deixa o outro credor" do
    operation = make_operation(@alfa)
    Accreditation.create!(tenant: @beta, operation: operation)
    caio = make_operation_user(operation, @alfa)
    Membership.create!(user: caio, tenant: @beta, profile: operator_profile(@beta), operation: operation)
    accreditation = Accreditation.find_by(tenant: @alfa, operation: operation)

    sign_in_as users(:joana)
    post settings_operation_status_url(accreditation), params: { accreditation: { status: "suspended", reason: "" } }
    assert_response :unprocessable_content
    post settings_operation_status_url(accreditation), params: { accreditation: { status: "suspended", reason: "pendência contratual" } }
    assert_predicate accreditation.reload, :suspended?
    delete session_url

    entrar(caio)
    assert_redirected_to root_url
    assert_equal I18n.t("operations.sign_in.suspended", operation: "Recupera", tenants: @alfa.name), flash[:alert]
  end

  test "R308: com todos os credenciamentos suspensos, a entrada diz isso em vez de 'inválido'" do
    operation = make_operation(@alfa)
    caio = make_operation_user(operation, @alfa)
    Accreditation.find_by(tenant: @alfa, operation: operation).update!(status: "suspended")
    entrar(caio)
    assert_redirected_to new_session_url
    assert_equal I18n.t("operations.sign_in.suspended", operation: "Recupera", tenants: @alfa.name), flash[:alert]
  end

  test "R310: o credor dá vínculo só com perfil disponível para operações" do
    operation = make_operation(@alfa)
    davi = User.create!(name: "Davi", email_address: "davi@recupera.com.br", password: "senha-de-teste-1")
    member = OperationMember.create!(operation: operation, user: davi)
    accreditation = Accreditation.find_by(tenant: @alfa, operation: operation)
    sign_in_as users(:joana)
    post settings_operation_links_url(accreditation), params: { link: { member_id: member.id, profile_id: profiles(:alfa_operator).id } }
    assert_response :unprocessable_content
    post settings_operation_links_url(accreditation), params: { link: { member_id: member.id, profile_id: operator_profile(@alfa).id } }
    assert_equal operation, davi.memberships.find_by(tenant: @alfa).operation
  end

  test "R310a e R327: o gestor da operação vê e cadastra só as pessoas da operação; dá vínculo só onde o credor deixa" do
    operation = make_operation(@alfa)
    lia = make_operation_user(operation, @alfa, email: "lia@recupera.com.br", name: "Lia", manager: true)
    make_operation_user(operation, @alfa)
    sign_in_as lia
    get operation_people_url
    assert_response :success
    assert_select "#menu-principal a", text: "Pessoas da operação"
    assert_select "tbody tr", 2
    assert_not_includes response.body, "joana@exemplo.com.br"
    post operation_people_url, params: { operation_member: { name: "Davi", email_address: "davi@recupera.com.br", manager: "0" } }
    davi = User.find_by(email_address: "davi@recupera.com.br")
    assert_equal operation, davi.operation_member.operation
    assert davi.temporary_password?

    member = davi.operation_member
    post operation_person_links_url(member), params: { link: { accreditation_id: Accreditation.find_by(tenant: @alfa).id, profile_id: operator_profile(@alfa).id } }
    assert_response :unprocessable_content
    @alfa.setting.update!(operation_manager_links: true)
    post operation_person_links_url(member), params: { link: { accreditation_id: Accreditation.find_by(tenant: @alfa).id, profile_id: operator_profile(@alfa).id } }
    assert davi.memberships.find_by(tenant: @alfa).active?
  end

  test "pessoa de operação que não é gestora não abre Pessoas da operação" do
    operation = make_operation(@alfa)
    sign_in_as make_operation_user(operation, @alfa)
    get operation_people_url
    assert_response :not_found
  end

  test "o perfil ganha a marca de disponível para operações" do
    sign_in_as users(:joana)
    patch profile_url(profiles(:alfa_operator)), params: { profile: { name: "Operador", available_to_operations: "1", permissions: Permission::OPERATOR } }
    assert profiles(:alfa_operator).reload.available_to_operations?
  end
end
