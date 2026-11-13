require "test_helper"

# Tela de sistemas (17, R396 a R399, R410, R427): lista, cadastro, edição, pausa, exclusão e a política "Cadastro entre sistemas". Permissão 23
# por credor e isolamento entre credores.
class SourceSystemsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @planilha = source_systems(:alfa_planilha)
  end

  def manager = SourceSystems::Manager.new(users(:joana))

  def sap(kind: "own_id") = manager.create(tenant: @alfa, name: "SAP", key_kind: kind)

  test "R427: sem a permissão 23 o menu não mostra Sistemas e o endereço responde 404, com a recusa registrada" do
    sign_in_as users(:carlos)
    assert_not_includes grupos_do_menu.values.flatten, "Sistemas"
    get source_systems_path, headers: TRECHO
    assert_response :not_found
    assert_equal "access_denied", AccessEvent.last.event
    assert_no_difference "SourceSystem.count" do
      post source_systems_path, params: { source_system: { tenant_id: @alfa.id, name: "SAP", key_kind: "own_id" } }, headers: TRECHO
    end
    assert_response :not_found
  end

  test "a lista mostra o CRM sem ações, o Planilha e os remotos do credor, e nada de outro credor" do
    sap
    SourceSystem.create!(tenant: @beta, name: "Totvs da Beta", key_kind: "natural")
    sign_in_as users(:joana)
    assert_includes grupos_do_menu["Entrada de dados"], "Sistemas"
    get source_systems_path, headers: TRECHO
    assert_response :success
    assert_select "h1", text: "Sistemas"
    assert_select "tbody tr th[scope=row]", text: "CRM"
    assert_select "tr#sistema-#{source_systems(:alfa_crm).id} td[data-acoes] a", 0
    assert_select "tr#sistema-#{@planilha.id} td", text: "Chave natural"
    assert_select "tbody tr th[scope=row]", text: "SAP"
    assert_select "tbody tr", text: /Id próprio/
    assert_select "tbody tr th[scope=row]", text: "Totvs da Beta", count: 0
    # O Planilha se edita e se pausa, mas não se exclui (R396).
    assert_select "tr#sistema-#{@planilha.id} td[data-acoes] a", text: "Editar"
    assert_select "tr#sistema-#{@planilha.id} td[data-acoes] a", text: "Pausar"
    assert_select "tr#sistema-#{@planilha.id} td[data-acoes] a", text: "Excluir", count: 0
  end

  test "a busca e a paginação refazem só o trecho da lista" do
    sap
    sign_in_as users(:joana)
    get source_systems_path(busca: "sa"), headers: TRECHO.merge("X-CRM-Fragmento" => "1")
    assert_response :success
    assert_select "h1", 0
    assert_select "tbody tr", 1
    assert_select "tbody tr th[scope=row]", text: "SAP"
  end

  test "R397: criar um sistema de id próprio fica registrado; o nome repetido volta com a mensagem" do
    sign_in_as users(:joana)
    get new_source_system_path, headers: TRECHO
    assert_response :success
    assert_select "input[name='source_system[name]']"
    assert_select "input[type=radio][name='source_system[key_kind]']", 2
    assert_difference "SourceSystem.count", 1 do
      post source_systems_path, params: { source_system: { tenant_id: @alfa.id, name: " SAP ", key_kind: "own_id" } }, headers: TRECHO
    end
    assert_response :no_content
    assert_equal "Sistema SAP criado.", evento_da_spa["aviso"]
    system = SourceSystem.find_by!(tenant: @alfa, name: "SAP")
    assert system.role_remote? && system.key_own_id? && system.active?
    change = Change.find_by!(subject_type: "source_system", subject_id: system.id, event: "created")
    assert_equal users(:joana).id, change.user_id

    assert_no_difference "SourceSystem.count" do
      post source_systems_path, params: { source_system: { tenant_id: @alfa.id, name: "sap", key_kind: "natural" } }, headers: TRECHO
    end
    assert_response :unprocessable_content
    assert_match "Nome já está em uso", response.body
  end

  test "criar em credor sem a permissão 23 responde 404" do
    sign_in_as users(:joana)
    assert_no_difference "SourceSystem.count" do
      post source_systems_path, params: { source_system: { tenant_id: @beta.id, name: "SAP", key_kind: "own_id" } }, headers: TRECHO
    end
    assert_response :not_found
  end

  test "R397: renomear e trocar o tipo de chave antes da primeira importação; depois dela o tipo fica travado" do
    system = sap
    sign_in_as users(:joana)
    patch source_system_path(system), params: { source_system: { name: "SAP ECC", key_kind: "natural" } }, headers: TRECHO
    assert_response :no_content
    assert system.reload.key_natural?
    assert_equal "SAP ECC", system.name
    assert_equal %w[key_kind_changed renamed], Change.where(subject_type: "source_system", subject_id: system.id).where.not(event: "created").pluck(:event).sort

    Import.create!(tenant: @alfa, user: users(:joana), kind: :portfolio, mode: :incremental, status: :confirmed, original_name: "c.csv", size_bytes: 10, source_system: system)
    get edit_source_system_path(system), headers: TRECHO
    assert_select "input[type=radio][name='source_system[key_kind]'][disabled]", 2
    patch source_system_path(system), params: { source_system: { name: "SAP ECC", key_kind: "own_id" } }, headers: TRECHO
    assert_response :unprocessable_content
    assert_match "não muda depois da primeira importação", response.body
    assert system.reload.key_natural?
  end

  test "R396: o CRM não se edita nem se pausa" do
    crm = source_systems(:alfa_crm)
    sign_in_as users(:joana)
    patch source_system_path(crm), params: { source_system: { name: "Outro" } }, headers: TRECHO
    assert_response :unprocessable_content
    assert_equal "CRM", crm.reload.name
    post source_system_pause_path(crm), headers: TRECHO
    assert_equal "danger", evento_da_spa["tom"]
    assert crm.reload.active?
  end

  test "R398: pausar e reativar ficam registrados" do
    system = sap
    sign_in_as users(:joana)
    post source_system_pause_path(system), headers: TRECHO
    assert_response :no_content
    assert system.reload.paused?
    assert_match "pausado", evento_da_spa["aviso"]
    delete source_system_pause_path(system), headers: TRECHO
    assert system.reload.active?
    assert_equal %w[paused resumed], Change.where(subject_type: "source_system", subject_id: system.id, event: %w[paused resumed]).order(:id).pluck(:event)
  end

  test "R399: sistema sem importação se exclui; com importação e o Planilha, não" do
    system = sap
    sign_in_as users(:joana)
    assert_difference "SourceSystem.count", -1 do
      delete source_system_path(system), headers: TRECHO
    end
    assert_equal "Sistema SAP excluído.", evento_da_spa["aviso"]
    assert Change.exists?(subject_type: "source_system", subject_id: system.id, event: "destroyed")

    used = sap
    Import.create!(tenant: @alfa, user: users(:joana), kind: :portfolio, mode: :incremental, status: :confirmed, original_name: "c.csv", size_bytes: 10, source_system: used)
    assert_no_difference "SourceSystem.count" do
      delete source_system_path(used), headers: TRECHO
      delete source_system_path(@planilha), headers: TRECHO
    end
    assert_equal "danger", evento_da_spa["tom"]
    assert_match "não pode ser excluído", evento_da_spa["aviso"]
  end

  test "o sistema definido na política do cadastro não se exclui enquanto a política aponta para ele" do
    system = sap
    manager.update_customer_record_policy(@alfa, policy: "defined_system", system_id: system.id)
    sign_in_as users(:joana)
    assert_no_difference "SourceSystem.count" do
      delete source_system_path(system), headers: TRECHO
    end
    assert_match "Cadastro entre sistemas", evento_da_spa["aviso"]
  end

  test "R410: a política só aparece com mais de um sistema além do CRM, e a troca fica no histórico" do
    sign_in_as users(:joana)
    get source_systems_path, headers: TRECHO
    assert_select "input[name=customer_record_policy]", 0

    system = sap
    get source_systems_path, headers: TRECHO
    assert_select "input[name=customer_record_policy]", 3
    assert_select "input[name=customer_record_policy][value=last_sender][checked]"
    assert_select "select[name=customer_record_system_id] option", text: "SAP"
    assert_select "select[name=customer_record_system_id] option", text: "CRM", count: 0

    patch source_systems_customer_record_policy_path, params: { credor: @alfa.id, customer_record_policy: "defined_system", customer_record_system_id: system.id }, headers: TRECHO
    assert_response :no_content
    setting = @alfa.setting.reload
    assert setting.customer_record_policy_defined_system?
    assert_equal system.id, setting.customer_record_system_id
    change = Change.find_by!(subject_type: "settings", subject_id: @alfa.id, field: "customer_record_policy")
    assert_equal [ "last_sender", "defined_system: SAP" ], [ change.before, change.after ]
    get source_systems_path, headers: TRECHO
    assert_match "Alterada por #{users(:joana).name}", response.body

    # Trocar para outra opção solta o sistema definido.
    patch source_systems_customer_record_policy_path, params: { credor: @alfa.id, customer_record_policy: "first_creator", customer_record_system_id: system.id }, headers: TRECHO
    assert_nil @alfa.setting.reload.customer_record_system_id
  end

  test "R410: um sistema definido exige o sistema, que precisa ser do credor e não o CRM" do
    sap
    sign_in_as users(:joana)
    [ nil, source_systems(:alfa_crm).id, source_systems(:beta_planilha).id ].each do |system_id|
      patch source_systems_customer_record_policy_path, params: { credor: @alfa.id, customer_record_policy: "defined_system", customer_record_system_id: system_id }, headers: TRECHO
      assert_equal "danger", evento_da_spa["tom"]
      assert_match "O sistema definido", evento_da_spa["aviso"]
    end
    assert @alfa.setting.reload.customer_record_policy_last_sender?
    patch source_systems_customer_record_policy_path, params: { credor: @beta.id, customer_record_policy: "first_creator" }, headers: TRECHO
    assert_response :not_found
  end

  test "na demonstração a tela abre, mas não altera" do
    previous = Rails.configuration.x.demo.enabled
    Rails.configuration.x.demo.enabled = true
    sign_in_as users(:joana)
    get source_systems_path, headers: TRECHO
    assert_response :success
    assert_no_difference "SourceSystem.count" do
      post source_systems_path, params: { source_system: { tenant_id: @alfa.id, name: "SAP", key_kind: "own_id" } }, headers: TRECHO
    end
  ensure
    Rails.configuration.x.demo.enabled = previous
  end
end
