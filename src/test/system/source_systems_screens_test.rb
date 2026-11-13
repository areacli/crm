require "application_system_test_case"
require "active_job/continuation/test_helper"

# Sistemas e identidade no navegador (17), nas abas da casca: a tela de sistemas, o envio que pergunta o sistema, as mudanças a confirmar da conferência,
# a simulação de acordo que pergunta o sistema e a escolha do contrato quando o código existe em mais de um. Tudo na SPA, fora do axe (plano da SPA, D7).
class SourceSystemsScreensSystemTest < ApplicationSystemTestCase
  include CsvHelper
  include ActiveJob::TestHelper
  include ActiveJob::Continuation::TestHelper

  JOAO = "390.533.447-05".freeze
  HEADER = (CsvHelper::HEADER + %w[id_titulo id_contrato id_cliente]).freeze

  setup do
    @alfa = tenants(:alfa)
    @joana = users(:joana)
  end

  def manager = SourceSystems::Manager.new(@joana)

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def carga(lines, system:, mode: :incremental)
    service = Portfolio::ImportService.new
    import = service.start(tenant: @alfa, user: @joana, file: write_csv(lines, header: HEADER), mode: mode, original_name: "carteira.csv", source_system: system)
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def confirmar(import)
    Portfolio::ImportService.new.confirm(import)
    2.times { perform_enqueued_jobs(only: ConfirmImportJob) }
  end

  test "a tela de sistemas lista o CRM e o Planilha, cria um sistema pelo diálogo e devolve o nome repetido com a mensagem" do
    entrar_na_casca
    abrir_aba source_systems_path
    assert_selector ".aba-raiz h1", text: "Sistemas", wait: 10
    assert_selector "[id='resultado'] .datagrid-row", text: "CRM"
    assert_selector "[id='resultado'] .datagrid-row", text: "Planilha"
    sem_rolagem_horizontal

    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar sistema").click
    no_dialogo do
      fill_in "Nome", with: "SAP"
      choose "Id próprio"
    end
    gravar_dialogo
    assert_aviso "Sistema SAP criado."
    assert_selector "[id='resultado'] .datagrid-row", text: "SAP", wait: 10
    sap = SourceSystem.find_by!(tenant: @alfa, name: "SAP")
    assert sap.key_own_id?

    # O nome repetido volta no próprio diálogo, com a mensagem.
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar sistema").click
    no_dialogo do
      fill_in "Nome", with: "sap"
    end
    gravar_dialogo(erro: true)
    no_dialogo { assert_text "Nome já está em uso" }
    assert_equal 1, SourceSystem.where(tenant: @alfa).where("lower(name) = 'sap'").count
  end

  test "o envio pergunta o sistema no credor com mais de um, e a conferência mostra as mudanças a confirmar, que a pessoa confirma na própria aba" do
    erp = manager.create(tenant: @alfa, name: "ERP", key_kind: "own_id")
    linha = ->(id, overrides = {}) { csv_line({ "id_titulo" => id, "id_contrato" => "K-1", "titulo" => "NF-#{id}" }.merge(overrides)) }
    confirmar(carga([ linha.call("T-1"), linha.call("T-2") ], system: erp))
    import = carga([ linha.call("T-1", "documento" => JOAO, "nome" => "João Pereira", "telefone" => "", "email" => ""), linha.call("T-2") ], system: erp)

    entrar_na_casca
    abrir_aba new_import_path
    assert_selector ".aba-raiz .filebox", wait: 10
    assert_selector ".aba-raiz label", text: "Sistema"
    escolher "Sistema", "ERP"
    assert_text "id_titulo" # as colunas de id aparecem para quem tem sistema remoto

    abrir_aba import_path(import)
    assert_selector ".aba-raiz #mudancas-a-confirmar h2", text: "Mudanças a confirmar: 1 a confirmar, 0 confirmadas", wait: 10
    within(".aba-raiz #mudancas-a-confirmar") do
      assert_text "Troca de devedor"
      assert_text "João Pereira"
      click_button "Confirmar mudança"
    end
    assert_aviso "1 mudança confirmada"
    assert_selector ".aba-raiz #mudancas-a-confirmar h2", text: "0 a confirmar, 1 confirmada", wait: 10
    assert_selector ".aba-raiz #mudancas-a-confirmar .situacao", text: "Confirmada"
    sem_rolagem_horizontal
    assert ImportRow.where(import_id: import.id).where.not(hold_kind: nil).sole.hold_confirmed
  end

  test "a simulação de acordo pergunta o sistema quando o cliente tem títulos em mais de um, e abre só com os títulos do escolhido" do
    customer, = agreement_scenario(@alfa)
    sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "natural")
    contract = Contract.create!(tenant: @alfa, source_system: sap, code: "K-5")
    ContractCustomer.create!(contract: contract, customer: customer)
    nf3 = Bill.create!(tenant: @alfa, contract: contract, customer: customer, number: "NF-3", due_date: Date.current - 60, amount_cents: 30_000, status: :active)

    entrar_na_casca
    abrir_aba new_customer_agreement_simulation_path(customer)
    assert_selector ".aba-raiz h2", text: "De qual sistema são os títulos do acordo?", wait: 10
    assert_selector ".aba-raiz tr", text: /Planilha\s*2/
    assert_selector ".aba-raiz tr", text: /SAP\s*1/
    sem_rolagem_horizontal

    find(".aba-raiz tr", text: "SAP").click_link("Simular")
    assert_selector ".simulacao form[data-calculo]", wait: 15
    assert_selector ".simulacao input[type=checkbox][name='agreement[bill_ids][]']", count: 1, visible: :all
    assert_selector ".simulacao input[id='titulo-#{nf3.id}']", visible: :all
    assert_selector ".aba-raiz a", text: "Trocar de sistema"
  end

  test "distribuir pelo código de contrato que existe em dois sistemas: o diálogo lista os dois e a pessoa escolhe" do
    operation = make_operation(@alfa)
    make_customer(@alfa, document: FakeData.cpf(801), name: "Ana Lima", contract_code: "C-7")
    sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "natural")
    twin = Contract.create!(tenant: @alfa, source_system: sap, code: "C-7")
    ContractCustomer.create!(contract: twin, customer: make_customer(@alfa, document: FakeData.cpf(802), name: "Bia Reis", contract_code: "C-8"))

    entrar_na_casca
    abrir_aba distributions_path
    assert_selector ".aba-raiz h1", text: "Distribuição", wait: 10
    find(".aba-raiz .cabecalho-da-pagina .botao", text: /\ADistribuir\z/).click
    no_dialogo do
      choose "Contrato (pelo código)"
      fill_in "Documento ou código", with: "C-7"
    end
    gravar_dialogo(erro: true)
    no_dialogo do
      assert_text "Há mais de um contrato com o código C-7 neste credor. Escolha um."
      assert_selector "label", text: "C-7 · Planilha · Ana Lima"
      choose "C-7 · SAP · Bia Reis"
    end
    gravar_dialogo
    assert_selector "[id='resultado'] .datagrid-row", text: "C-7", wait: 10
    assert_equal twin, Distribution.where(operation: operation).sole.contract
  end
end
