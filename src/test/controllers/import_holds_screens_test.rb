require "test_helper"
require "active_job/continuation/test_helper"

# Mudanças a confirmar na conferência da carteira (17, R409a) e o que a carga por sistema deixa à vista: o que o "Confirmar" diz antes de gravar e
# o nome mantido no histórico do cadastro (R411).
class ImportHoldsScreensTest < ActionDispatch::IntegrationTest
  include CsvHelper
  include ActiveJob::TestHelper
  include ActiveJob::Continuation::TestHelper

  MARIA = "529.982.247-25".freeze
  JOAO = "390.533.447-05".freeze
  HEADER = (CsvHelper::HEADER + %w[id_titulo id_contrato id_cliente]).freeze

  setup do
    @joana = users(:joana)
    @alfa = tenants(:alfa)
    @service = Portfolio::ImportService.new
    @erp = SourceSystems::Manager.new(@joana).create(tenant: @alfa, name: "ERP", key_kind: "own_id")
  end

  def entrar(usuario) = post(session_path, params: { email_address: usuario.email_address, password: "senha-de-teste-1" })

  def send_file(lines, system: @erp, mode: :incremental)
    import = @service.start(tenant: @alfa, user: @joana, file: write_csv(lines, header: HEADER), mode: mode, original_name: "carteira.csv", source_system: system)
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def confirm(import)
    @service.confirm(import)
    2.times { perform_enqueued_jobs(only: ConfirmImportJob) }
    import.reload
  end

  def erp_line(bill_id, overrides = {}) = csv_line({ "id_titulo" => bill_id, "id_contrato" => "K-1" }.merge(overrides))

  def joao(bill_id, overrides = {}) = erp_line(bill_id, { "documento" => JOAO, "nome" => "João Pereira", "telefone" => "", "email" => "" }.merge(overrides))

  # Dois títulos da Maria no ERP e uma carga em batimento que passa os dois ao João: duas trocas de devedor a confirmar, e o T-3 sai.
  def conferida_com_duas_trocas
    confirm(send_file([ erp_line("T-1", "titulo" => "NF-1"), erp_line("T-2", "titulo" => "NF-2"), erp_line("T-3", "titulo" => "NF-3") ]))
    send_file([ joao("T-1", "titulo" => "NF-1"), joao("T-2", "titulo" => "NF-2") ], mode: :full_sync)
  end

  def held(import) = ImportRow.where(import_id: import.id).where.not(hold_kind: nil).order(:line)

  # O texto do diálogo que o botão "Confirmar" abre (a mensagem viaja no endereço, assinada).
  def mensagem_do_confirmar
    link = css_select("a[data-spa-dialogo]").find { |node| node.text.strip == "Confirmar" }
    get link["href"], headers: TRECHO
    assert_response :success
    response.body
  end

  test "a conferência mostra as mudanças a confirmar, com o cliente de hoje, o que a carga traz e a ação de cada linha" do
    import = conferida_com_duas_trocas
    entrar(@joana)
    get import_path(import), headers: TRECHO

    assert_response :success
    assert_select "#mudancas-a-confirmar h2", /Mudanças a confirmar: 2 a confirmar, 0 confirmadas/
    assert_select "#mudancas-a-confirmar tbody tr", 2
    assert_select "#mudancas-a-confirmar tbody tr:first-child" do
      assert_select "th", /NF-1.*id T-1/m
      assert_select "td", "Troca de devedor"
      assert_select "td", "Maria da Silva"
      assert_select "td", "João Pereira"
      assert_select ".situacao", "A confirmar"
      assert_select "button", "Confirmar mudança"
    end
    assert_select "#mudancas-a-confirmar button", "Confirmar todas as mudanças"
    assert_select "#mudancas-a-confirmar button", text: "Desfazer todas as confirmações", count: 0
    assert_select "dt", "Sistema"
    assert_select "dd", "ERP"
  end

  test "confirmar uma linha, desfazer e confirmar todas: a tela acompanha e o Confirmar diz o que entra, o que fica e o que sai do sistema" do
    import = conferida_com_duas_trocas
    line = held(import).first.line
    entrar(@joana)

    post import_holds_path(import, linha: line), headers: TRECHO
    assert_response :no_content
    assert_match "1 mudança confirmada", evento_da_spa["aviso"].to_s
    assert_equal [ true, false ], held(import).pluck(:hold_confirmed)

    get import_path(import), headers: TRECHO
    assert_select "#mudancas-a-confirmar h2", /1 a confirmar, 1 confirmada/
    assert_select "#mudancas-a-confirmar tbody tr:first-child .situacao", "Confirmada"
    assert_select "#mudancas-a-confirmar tbody tr:first-child button", "Desfazer"
    assert_select "#mudancas-a-confirmar button", "Desfazer todas as confirmações"
    mensagem = mensagem_do_confirmar
    assert_match "Das 2 mudanças a confirmar, 1 será aplicada e 1 fica como está.", mensagem
    assert_match "Será retirado 1 título do ERP: os que não vieram no arquivo saem da cobrança.", mensagem

    delete import_holds_path(import, linha: line), headers: TRECHO
    assert_response :no_content
    assert_match "1 confirmação desfeita", evento_da_spa["aviso"].to_s
    assert_equal [ false, false ], held(import).pluck(:hold_confirmed)

    post import_holds_path(import), headers: TRECHO
    assert_match "2 mudanças confirmadas", evento_da_spa["aviso"].to_s
    assert_equal [ true, true ], held(import).pluck(:hold_confirmed)
    post import_holds_path(import), headers: TRECHO
    assert_match "Nenhuma mudança a confirmar", evento_da_spa["aviso"].to_s

    delete import_holds_path(import), headers: TRECHO
    assert_match "2 confirmações desfeitas", evento_da_spa["aviso"].to_s
    assert_equal [ false, false ], held(import).pluck(:hold_confirmed)
  end

  test "título com promessa em aberto aparece bloqueado, sem ação, e não entra no confirmar todas" do
    confirm(send_file([ erp_line("T-1", "titulo" => "NF-1") ]))
    maria = Customer.find_by!(tenant: @alfa, document: Document.normalize(MARIA))
    register_promise(maria, [ Bill.find_by!(tenant: @alfa, source_system: @erp, external_id: "T-1") ])
    import = send_file([ joao("T-1", "titulo" => "NF-1") ])
    entrar(@joana)

    get import_path(import), headers: TRECHO
    assert_select "#mudancas-a-confirmar h2", /0 a confirmar, 0 confirmadas, 1 bloqueada/
    assert_select "#mudancas-a-confirmar .situacao", "Bloqueada"
    assert_select "#mudancas-a-confirmar small", Portfolio::Holds::PROMISE
    assert_select "#mudancas-a-confirmar button", count: 0
    assert_match "A mudança a confirmar fica como está.", mensagem_do_confirmar

    post import_holds_path(import), headers: TRECHO
    assert_match "Nenhuma mudança a confirmar", evento_da_spa["aviso"].to_s
    assert_equal [ false ], held(import).pluck(:hold_confirmed)
  end

  test "quem não confirma importações não confirma mudança, e a importação já confirmada não aceita mais" do
    import = conferida_com_duas_trocas
    entrar(users(:carlos))
    post import_holds_path(import), headers: TRECHO
    assert_response :not_found
    assert_equal [ false, false ], held(import).pluck(:hold_confirmed)

    entrar(@joana)
    confirm(import)
    post import_holds_path(import), headers: TRECHO
    assert_response :not_found
    get import_path(import), headers: TRECHO
    assert_response :success
    assert_select "#mudancas-a-confirmar", count: 0
  end

  test "R411: o nome que não prevaleceu aparece no histórico do cadastro, com o sistema que o informou" do
    planilha = source_systems(:alfa_planilha)
    confirm(send_file([ csv_line ], system: planilha))
    SourceSystems::Manager.new(@joana).update_customer_record_policy(@alfa, policy: "defined_system", system_id: planilha.id)
    confirm(send_file([ erp_line("T-1", "nome" => "Maria S. Oliveira", "titulo" => "NF-9") ]))
    maria = Customer.find_by!(tenant: @alfa, document: Document.normalize(MARIA))
    entrar(@joana)

    get_ficha(maria, aba: "historico")
    assert_response :success
    assert_equal "Maria da Silva", maria.name
    assert_select "#historico-do-cadastro", /nome mantido: Maria da Silva \(ERP informou Maria S\. Oliveira\)/
  end
end
