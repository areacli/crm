require "test_helper"

# O sistema nas telas (17, R412, R422, R423, R424): com um sistema só além do CRM, nada muda; com mais de um, a ficha diz de que sistema é cada contrato e
# cada título, quem informou o contato e de que sistema veio a mudança da carga. A busca da lista acha o cliente pelo id dele num sistema.
class SystemsOnScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @bill = make_bill(@alfa, number: "NF-1", contract_code: "CT-1")
    @maria = @bill.customer
    @contract = @bill.contract
    @sheet = SourceSystem.default_of(@alfa.id)
    post session_path, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
  end

  def with_sap
    @sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "own_id")
    Contract.where(id: @contract.id).update_all(source_system_id: @sap.id, external_id: "CTR-9")
    Bill.where(id: @bill.id).update_all(source_system_id: @sap.id, external_id: "T-77")
  end

  test "R422: com um sistema só, a ficha e a página do título não falam de sistema" do
    get_ficha(@maria)
    assert_select "#contratos th", text: "Sistema", count: 0
    assert_select "th", text: "Sistema", count: 0
    get bill_path(@bill), headers: TRECHO
    assert_response :success
    assert_no_match(/Sistema Planilha/, response.body)
  end

  test "R422: com mais de um sistema, o contrato e o título mostram o sistema, e o id remoto fica no detalhe do contrato e na página do título" do
    with_sap
    crm_title = Bill.create!(tenant: @alfa, contract: @contract, customer: @maria, number: "ACD-1/1", due_date: Date.current + 10, amount_cents: 5_000, status: :active)
    Bill.where(id: crm_title.id).update_all(source_system_id: SourceSystem.crm_of(@alfa.id).id)

    get_ficha(@maria)
    assert_select "#contratos th", text: "Sistema", count: 1
    assert_select "#contratos td", text: "SAP"
    assert_select "#contratos .detalhe-da-linha p", text: "Id no sistema SAP: CTR-9."
    # A coluna dos títulos mostra o pai de cada um: o que o CRM criou é do CRM, mesmo num contrato do SAP.
    assert_select "td", text: "CRM", minimum: 1

    get bill_path(@bill), headers: TRECHO
    assert_match(/Sistema SAP \(id T-77\)/, response.body)
  end

  test "R412: o contato diz quais sistemas o informaram" do
    with_sap
    contact = add_contact(@maria, "phone", "(11) 91111-1111", origin: "load")
    contact.update_columns(source_system_ids: [ @sap.id, @sheet.id ])
    get_ficha(@maria, aba: "contatos")
    assert_select "p", text: "Informado por: Planilha e SAP."
  end

  test "R423: a mudança que veio de uma carga diz de que sistema, quando o credor tem mais de um" do
    contact = add_contact(@maria, "phone", "(11) 91111-1111", origin: "load")
    Change.create!(tenant_id: @alfa.id, subject_type: "customer_contact", subject_id: contact.id, event: "created", after: "valid", source_system_id: @sheet.id, occurred_at: Time.current)
    get_ficha(@maria, aba: "historico")
    assert_select "#historico-do-cadastro tbody td", text: "carga", count: 1

    with_sap
    Change.create!(tenant_id: @alfa.id, subject_type: "customer", subject_id: @maria.id, event: "updated", field: "name", before: "Maria S.", after: "Maria Souza",
                   source_system_id: @sap.id, occurred_at: Time.current)
    get_ficha(@maria, aba: "historico")
    assert_select "#historico-do-cadastro tbody td", text: "carga do sistema SAP", count: 1
    assert_select "#historico-do-cadastro tbody td", text: "carga do sistema Planilha", count: 1
  end

  test "R424: a busca da lista acha o cliente pelo id dele num sistema, só no credor de quem busca" do
    with_sap
    CustomerIdentity.create!(tenant: @alfa, source_system: @sap, customer: @maria, external_id: "BP-1")
    other = make_customer(tenants(:beta), name: "Cliente da Beta")
    CustomerIdentity.create!(tenant: tenants(:beta), source_system: SourceSystem.default_of(tenants(:beta).id), customer: other, external_id: "BP-77")

    assert_equal [ "Maria Souza" ], linhas_de_clientes(busca: "BP-1").map { |linha| celula(linha, "name") }
    assert_equal [ "Maria Souza" ], linhas_de_clientes(busca: " BP-1 ").map { |linha| celula(linha, "name") }
    assert_empty linhas_de_clientes(busca: "BP-77"), "identidade de outro credor não aparece"
    assert_equal [ "Maria Souza" ], linhas_de_clientes(busca: "maria").map { |linha| celula(linha, "name") }, "a busca por nome segue como era"
  end
end
