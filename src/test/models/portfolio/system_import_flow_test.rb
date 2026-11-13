require "test_helper"
require "active_job/continuation/test_helper"

# Carteira por sistema (17, R400 a R415, R423): a carga entra por um sistema do credor e só casa com contratos e títulos dele, pela chave dele; o
# cliente é um só por credor e documento, com identidades remotas; a troca de devedor e o id de cliente com outro documento esperam o gestor.
class Portfolio::SystemImportFlowTest < ActiveSupport::TestCase
  include ActiveJob::Continuation::TestHelper

  MARIA = "529.982.247-25".freeze
  JOAO = "390.533.447-05".freeze
  ANA = "111.444.777-35".freeze
  HEADER = (CsvHelper::HEADER + %w[id_titulo id_contrato id_cliente]).freeze

  setup do
    @tenant = tenants(:alfa)
    @user = users(:joana)
    @service = Portfolio::ImportService.new
    @planilha = source_systems(:alfa_planilha)
    manager = SourceSystems::Manager.new(@user)
    @sap = manager.create(tenant: @tenant, name: "SAP", key_kind: "natural")
    @erp = manager.create(tenant: @tenant, name: "ERP", key_kind: "own_id")
  end

  def send_file(lines, system: nil, mode: :incremental, tenant: @tenant)
    import = @service.start(tenant: tenant, user: @user, file: write_csv(lines, header: HEADER), mode: mode, original_name: "carteira.csv", source_system: system)
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def confirm(import)
    @service.confirm(import)
    2.times { perform_enqueued_jobs(only: ConfirmImportJob) }
    import.reload
  end

  def load(lines, **options) = confirm(send_file(lines, **options))

  def joao(overrides = {}) = csv_line({ "documento" => JOAO, "nome" => "João Pereira", "telefone" => "", "email" => "" }.merge(overrides))

  # Linha de um sistema de id próprio: o título e o contrato pelo id.
  def erp_line(bill_id, overrides = {}) = csv_line({ "id_titulo" => bill_id, "id_contrato" => "K-1" }.merge(overrides))

  def customer(document) = Customer.find_by(tenant: @tenant, document: Document.normalize(document))

  def erp_bill(id) = Bill.find_by(tenant: @tenant, source_system: @erp, external_id: id)

  def held_line(import, kind = nil) = ImportRow.where(import_id: import.id).where.not(hold_kind: nil).where(kind ? { hold_kind: kind } : {}).order(:line).pick(:line)

  def ignored(import) = import.rejections.where(ignored: true).order(:line).pluck(:reason)

  test "R400: sem escolha a carga entra pelo Planilha; sistema pausado ou de outro credor recusa o envio" do
    assert_equal @planilha, send_file([ csv_line ]).source_system

    SourceSystems::Manager.new(@user).pause(@sap)
    error = assert_raises(Portfolio::ImportRefused) { send_file([ csv_line ], system: @sap) }
    assert_equal "o sistema SAP está pausado", error.message
    error = assert_raises(Portfolio::ImportRefused) { send_file([ csv_line ], system: source_systems(:beta_planilha)) }
    assert_equal "o sistema escolhido não é deste credor", error.message
  end

  test "R403 e R404: em chave natural, o mesmo documento e número em dois sistemas são dois títulos, cada um no contrato do seu sistema" do
    lines = ->(value) { [ csv_line("titulo" => "NF-1", "valor" => value), csv_line("titulo" => "NF-9", "contrato" => "", "valor" => value) ] }
    load(lines.call("100,00"))
    second = send_file(lines.call("250,00"), system: @sap)

    # A conferência compara só com o que é do sistema: para o SAP, os dois títulos são novos e o cliente já existe.
    summary = second.summary_data
    assert_equal [ 2, 2, 0, 0 ], [ summary[:valid], summary[:bills_new], summary[:bills_updated], summary[:customers_new] ]
    assert_equal 1, summary[:contracts_created_by_omission]
    confirm(second)

    assert_equal 1, Customer.where(tenant: @tenant).count
    assert_equal [ @planilha.id, @sap.id ], customer(MARIA).source_system_ids
    assert_equal({ @planilha.id => [ 10_000, 10_000 ], @sap.id => [ 25_000, 25_000 ] }, Bill.where(tenant: @tenant).order(:number).group_by(&:source_system_id).transform_values { |bills| bills.map(&:amount_cents) })
    assert_equal [ [ @planilha.id, "CT-1" ], [ @sap.id, "CT-1" ] ], Contract.where(tenant: @tenant, created_by_omission: false).order(:id).pluck(:source_system_id, :code)
    assert_equal [ @planilha.id, @sap.id ], Contract.where(tenant: @tenant, created_by_omission: true).order(:id).pluck(:source_system_id)
    assert Bill.where(tenant: @tenant).all? { |bill| bill.source_system_id == bill.contract.source_system_id }

    # A carga seguinte do SAP atualiza só o título do SAP, e o registro guarda o sistema (R423); o contrato por omissão dele é reaproveitado.
    third = load([ csv_line("titulo" => "NF-1", "valor" => "300,00"), csv_line("titulo" => "NF-9", "contrato" => "", "valor" => "250,00") ], system: @sap)
    assert_equal [ 10_000, 30_000 ], Bill.where(tenant: @tenant, number: "NF-1").order(:source_system_id).pluck(:amount_cents)
    change = Change.find_by!(import_id: third.id, field: "amount_cents")
    assert_equal [ @sap.id, "25000", "30000" ], [ change.source_system_id, change.before, change.after ]
    assert_equal 4, Bill.where(tenant: @tenant).count
    assert_equal 2, Contract.where(tenant: @tenant, created_by_omission: true).count
  end

  test "R401 e R402: em id próprio, id do título e id do contrato são obrigatórios e o id repetido no arquivo segue a R4" do
    import = send_file([ erp_line("T-1"), erp_line("", "titulo" => "NF-2"), erp_line("T-3", "titulo" => "NF-3", "id_contrato" => ""),
                         erp_line("T-1", "titulo" => "NF-4", "documento" => JOAO, "nome" => "João Pereira") ], system: @erp)

    assert_equal 1, import.summary_data[:valid]
    assert_equal [ "id do título obrigatório neste sistema", "id do contrato obrigatório neste sistema", "título repetido na linha 2" ], import.rejections.order(:line).pluck(:reason)
  end

  test "R401: em chave natural, id do título e id do contrato são colunas ignoradas, e o título segue pelo documento e número" do
    import = load([ csv_line("id_titulo" => "T-1", "id_contrato" => "K-1") ], system: @sap)

    assert_equal %w[id_titulo id_contrato], import.summary_data[:ignored_columns]
    bill = Bill.find_by!(tenant: @tenant, source_system: @sap)
    assert_nil bill.external_id
    assert_nil bill.contract.external_id
  end

  test "R405 e R406: em id próprio, título e contrato são achados pelo id; número e código são dados, atualizados com histórico" do
    load([ erp_line("T-1", "titulo" => "NF-1"), erp_line("T-2", "titulo" => "NF-2") ], system: @erp)
    contract = Contract.find_by!(tenant: @tenant, source_system: @erp)
    assert_equal [ "K-1", "CT-1", false ], [ contract.external_id, contract.code, contract.created_by_omission ]
    assert_equal %w[NF-1 NF-2], [ erp_bill("T-1").number, erp_bill("T-2").number ]

    second = send_file([ erp_line("T-1", "titulo" => "NF-2", "contrato" => "CT-NOVO"), erp_line("T-2", "titulo" => "NF-2", "contrato" => "CT-NOVO") ], system: @erp)
    assert_equal [ 0, 1, 1 ], second.summary_data.values_at(:bills_new, :bills_updated, :bills_unchanged)
    confirm(second)

    # O mesmo número em dois títulos do mesmo cliente cabe em id próprio (R406): o título é o id.
    assert_equal 2, Bill.where(tenant: @tenant, source_system: @erp).count
    assert_equal %w[NF-2 NF-2], [ erp_bill("T-1").number, erp_bill("T-2").number ]
    assert_equal "CT-NOVO", contract.reload.code
    number = Change.find_by!(import_id: second.id, subject_type: "bill", field: "number")
    assert_equal [ "NF-1", "NF-2", @erp.id, erp_bill("T-1").id ], [ number.before, number.after, number.source_system_id, number.subject_id ]
    code = Change.find_by!(import_id: second.id, subject_type: "contract", field: "code")
    assert_equal [ "CT-1", "CT-NOVO", @erp.id ], [ code.before, code.after, code.source_system_id ]
    assert_equal 1, Contract.where(tenant: @tenant, source_system: @erp).count
  end

  test "R407 a R409: o id de cliente vira identidade do sistema, e a ligação com o contrato guarda a mais recente" do
    load([ csv_line("id_cliente" => "C-1") ], system: @sap)
    maria = customer(MARIA)
    identity = CustomerIdentity.find_by!(tenant: @tenant, source_system: @sap, external_id: "C-1")
    link = ContractCustomer.find_by!(customer: maria)
    assert_equal [ maria, identity ], [ identity.customer, link.customer_identity ]

    # Outro id para o mesmo documento é outra identidade do mesmo cliente; a ligação passa a guardar a que chegou por último.
    load([ csv_line("id_cliente" => "C-2", "titulo" => "NF-2") ], system: @sap)
    assert_equal %w[C-1 C-2], maria.identities.order(:id).pluck(:external_id)
    assert_equal "C-2", link.reload.customer_identity.external_id

    # O mesmo id em outro sistema é de outro espaço de nomes: não é mudança a confirmar.
    other = send_file([ joao("id_cliente" => "C-1") ])
    assert_equal 0, other.summary_data.dig(:holds, :count)
    confirm(other)
    assert_equal customer(JOAO), CustomerIdentity.find_by!(tenant: @tenant, source_system: @planilha, external_id: "C-1").customer
    assert_equal maria, identity.reload.customer
  end

  test "R402: o mesmo id de cliente com documentos diferentes no arquivo recusa as linhas do id" do
    import = send_file([ csv_line("id_cliente" => "C-1"), joao("id_cliente" => "C-1", "titulo" => "NF-2"), csv_line("documento" => ANA, "nome" => "Ana Souza", "titulo" => "NF-3") ], system: @sap)

    assert_equal 1, import.summary_data[:valid]
    assert_equal [ "documentos diferentes para o mesmo id de cliente: linhas 2 e 3" ] * 2, import.rejections.order(:line).pluck(:reason)
  end

  test "R409a: o id de cliente que já é de outro documento fica seguro; sem confirmação a linha não é aplicada e vai ao resultado" do
    load([ csv_line("id_cliente" => "C-1") ], system: @sap)
    import = send_file([ joao("id_cliente" => "C-1", "titulo" => "NF-7"), csv_line("documento" => ANA, "nome" => "Ana Souza", "titulo" => "NF-8") ], system: @sap)

    summary = import.summary_data
    assert_equal({ count: 1, blocked: 0 }, summary[:holds].to_h.symbolize_keys)
    assert_equal [ 2, 1 ], [ summary[:valid], summary[:bills_new] ]
    assert_equal "identity", ImportRow.find_by!(import_id: import.id, line: held_line(import)).hold_kind

    confirm(import)
    assert import.confirmed?
    assert_equal({ count: 1, blocked: 0, confirmed: 0, unapplied: 1 }, import.summary_data[:holds].to_h.symbolize_keys)
    assert_equal 1, import.summary_data[:valid]
    assert_equal [ Portfolio::Holds::UNCONFIRMED.fetch("identity") ], ignored(import)
    assert_nil customer(JOAO)
    assert_equal customer(MARIA), CustomerIdentity.find_by!(source_system: @sap, external_id: "C-1").customer
    assert_equal %w[NF-1 NF-8], Bill.where(tenant: @tenant, source_system: @sap).order(:number).pluck(:number)
  end

  test "R409a: confirmada, a identidade passa ao novo documento, com histórico, e a ligação antiga deixa de citá-la" do
    load([ csv_line("id_cliente" => "C-1") ], system: @sap)
    maria = customer(MARIA)
    import = send_file([ joao("id_cliente" => "C-1", "titulo" => "NF-7", "contrato" => "CT-7") ], system: @sap)
    assert_equal 1, Portfolio::Holds.new(import).confirm(held_line(import))

    confirm(import)
    assert_equal({ count: 1, blocked: 0, confirmed: 1, unapplied: 0 }, import.summary_data[:holds].to_h.symbolize_keys)
    assert_empty ignored(import)
    identity = CustomerIdentity.find_by!(source_system: @sap, external_id: "C-1")
    joao = customer(JOAO)
    assert_equal joao, identity.customer
    assert_nil ContractCustomer.find_by!(customer: maria).customer_identity_id
    assert_equal identity, ContractCustomer.find_by!(customer: joao).customer_identity
    change = Change.find_by!(import_id: import.id, subject_type: "customer_identity", event: "customer_changed")
    # O registro guarda os ids dos clientes, nunca nome nem documento.
    assert_equal [ maria.id.to_s, joao.id.to_s, @sap.id, "load" ], [ change.before, change.after, change.source_system_id, change.origin ]
    assert_equal "NF-7", Bill.find_by!(customer: joao).number
  end

  test "R405 e R409a: em id próprio, a troca de devedor fica segura; sem confirmação o título fica como estava e não sai no batimento" do
    load([ erp_line("T-1", "titulo" => "NF-1"), erp_line("T-2", "titulo" => "NF-2") ], system: @erp)
    maria = customer(MARIA)
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-2", "titulo" => "NF-1"),
                         csv_line("documento" => ANA, "nome" => "Ana Souza", "titulo" => "NF-3", "id_titulo" => "T-3", "id_contrato" => "K-3") ], system: @erp, mode: :full_sync)

    summary = import.summary_data
    assert_equal({ count: 1, blocked: 0 }, summary[:holds].to_h.symbolize_keys)
    # A linha segura não conta como título novo nem atualizado, e o título dela veio no arquivo: só o T-2 sai.
    assert_equal [ 2, 1, 0, 1 ], [ summary[:valid], summary[:bills_new], summary[:bills_updated], summary.dig(:to_withdraw, :count) ]
    assert_equal "debtor", ImportRow.find_by!(import_id: import.id, line: held_line(import)).hold_kind

    confirm(import)
    assert_equal [ Portfolio::Holds::UNCONFIRMED.fetch("debtor") ], ignored(import)
    assert_equal [ maria.id, "active" ], erp_bill("T-1").then { |bill| [ bill.customer_id, bill.status ] }
    assert_equal "withdrawn", erp_bill("T-2").status
    assert_equal "active", erp_bill("T-3").status
    assert_nil customer(JOAO)
    assert_nil Contract.find_by(tenant: @tenant, source_system: @erp, external_id: "K-2")
  end

  test "R405 e R409a: confirmada, a troca de devedor passa o título ao cliente da linha, com os ids dos clientes no histórico" do
    load([ erp_line("T-1", "titulo" => "NF-1") ], system: @erp)
    maria = customer(MARIA)
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-2", "titulo" => "NF-1", "contrato" => "CT-2") ], system: @erp)
    assert_equal 1, Portfolio::Holds.new(import).confirm

    confirm(import)
    joao = customer(JOAO)
    bill = erp_bill("T-1")
    assert_equal [ joao.id, "K-2", "active" ], [ bill.customer_id, bill.contract.external_id, bill.status ]
    assert_equal 1, Bill.where(tenant: @tenant, source_system: @erp).count
    change = Change.find_by!(import_id: import.id, subject_type: "bill", event: "customer_changed")
    assert_equal [ maria.id.to_s, joao.id.to_s, @erp.id ], [ change.before, change.after, change.source_system_id ]
    assert_equal({ count: 1, blocked: 0, confirmed: 1, unapplied: 0 }, import.summary_data[:holds].to_h.symbolize_keys)
    assert_empty ignored(import)
  end

  test "R409a: a linha que troca o devedor e traz id de cliente de outro documento é uma mudança só, e confirmada aplica as duas" do
    load([ erp_line("T-1", "titulo" => "NF-1", "id_cliente" => "C-1") ], system: @erp)
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-1", "titulo" => "NF-1", "id_cliente" => "C-1") ], system: @erp)
    assert_equal({ count: 1, blocked: 0 }, import.summary_data[:holds].to_h.symbolize_keys)
    assert_equal "both", ImportRow.find_by!(import_id: import.id, line: held_line(import)).hold_kind
    Portfolio::Holds.new(import).confirm

    confirm(import)
    joao = customer(JOAO)
    assert_equal joao.id, erp_bill("T-1").customer_id
    assert_equal joao, CustomerIdentity.find_by!(source_system: @erp, external_id: "C-1").customer
  end

  test "R409a: confirma item a item ou todas, desfaz, e só as confirmadas entram" do
    load([ erp_line("T-1", "titulo" => "NF-1"), erp_line("T-2", "titulo" => "NF-2") ], system: @erp)
    maria = customer(MARIA)
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-2", "titulo" => "NF-1"), joao("id_titulo" => "T-2", "id_contrato" => "K-2", "titulo" => "NF-2") ], system: @erp)
    holds = Portfolio::Holds.new(import)
    first, second = ImportRow.where(import_id: import.id).where.not(hold_kind: nil).order(:line).pluck(:line)

    assert_equal [ 2, 0, 0, 2 ], holds.counts.then { |counts| [ counts.total, counts.blocked, counts.confirmed, counts.pending ] }
    assert_equal 1, holds.confirm(first)
    assert_equal 0, holds.confirm(first)
    assert_equal 1, holds.confirm
    assert_equal 2, holds.counts.confirmed
    assert_equal 2, holds.undo
    assert_equal 1, holds.confirm(second)
    assert_equal 1, holds.undo(second)
    assert_equal 1, holds.confirm(first)
    assert_equal [ "Maria da Silva", "Maria da Silva" ], holds.listing.map(&:debtor)

    confirm(import)
    assert_equal({ count: 2, blocked: 0, confirmed: 1, unapplied: 1 }, import.summary_data[:holds].to_h.symbolize_keys)
    assert_equal [ customer(JOAO).id, maria.id ], [ erp_bill("T-1").customer_id, erp_bill("T-2").customer_id ]
    assert_equal [ Portfolio::Holds::UNCONFIRMED.fetch("debtor") ], ignored(import)
  end

  test "R409a: título com promessa em aberto não pode ser confirmado e aparece com o motivo" do
    load([ erp_line("T-1", "titulo" => "NF-1", "vencimento" => "15/07/2026") ], system: @erp)
    maria = customer(MARIA)
    register_promise(maria, [ erp_bill("T-1") ])
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-1", "titulo" => "NF-1") ], system: @erp, mode: :full_sync)

    assert_equal({ count: 1, blocked: 1 }, import.summary_data[:holds].to_h.symbolize_keys)
    holds = Portfolio::Holds.new(import)
    assert_equal Portfolio::Holds::PROMISE, holds.items.first.hold_blocked_reason
    assert_equal 0, holds.confirm
    assert_equal 0, holds.counts.pending

    confirm(import)
    assert_equal [ "troca de devedor não aplicada: título com promessa em aberto" ], ignored(import)
    assert_equal [ maria.id, "active" ], erp_bill("T-1").then { |bill| [ bill.customer_id, bill.status ] }
    assert_equal({ count: 1, blocked: 1, confirmed: 0, unapplied: 1 }, import.summary_data[:holds].to_h.symbolize_keys)
  end

  test "R57: o título pago de outro cliente não é mudança a confirmar, e a carga não o atualiza" do
    load([ erp_line("T-1", "titulo" => "NF-1") ], system: @erp)
    maria = customer(MARIA)
    erp_bill("T-1").update_columns(status: "paid", paid_on: Date.current)
    import = send_file([ joao("id_titulo" => "T-1", "id_contrato" => "K-1", "titulo" => "NF-1") ], system: @erp)

    assert_equal 0, import.summary_data.dig(:holds, :count)
    confirm(import)
    assert_equal [ maria.id, "paid" ], erp_bill("T-1").then { |bill| [ bill.customer_id, bill.status ] }
    assert_empty ignored(import)
  end

  test "R410 e R411: com o último a enviar, a carga de qualquer sistema muda o nome, com o sistema no histórico" do
    load([ csv_line ])
    import = load([ csv_line("nome" => "Maria S. Santos", "titulo" => "NF-2") ], system: @sap)

    assert_equal "Maria S. Santos", customer(MARIA).name
    change = Change.find_by!(import_id: import.id, subject_type: "customer", field: "name")
    assert_equal [ "updated", "Maria da Silva", "Maria S. Santos", @sap.id ], [ change.event, change.before, change.after, change.source_system_id ]
  end

  test "R411: com o sistema definido, a carga dos outros não muda o nome; o que ela trazia fica no histórico, uma vez por nome" do
    load([ csv_line ])
    @tenant.setting.update!(customer_record_policy: "defined_system", customer_record_system: @planilha)
    line = csv_line("nome" => "Maria S. Santos", "titulo" => "NF-2")
    import = load([ line ], system: @sap)

    maria = customer(MARIA)
    assert_equal "Maria da Silva", maria.name
    assert_equal [ @planilha.id, @sap.id ], maria.source_system_ids
    ignored_name = Change.find_by!(import_id: import.id, event: "name_ignored")
    assert_equal [ "customer", maria.id, "name", "Maria da Silva", "Maria S. Santos", @sap.id, "cadastro entre sistemas: SAP não prevalece" ],
                 [ ignored_name.subject_type, ignored_name.subject_id, ignored_name.field, ignored_name.before, ignored_name.after, ignored_name.source_system_id, ignored_name.note ]
    assert Bill.exists?(tenant: @tenant, source_system: @sap, number: "NF-2")

    # A carga diária do SAP não repete o registro; outro nome é outro registro.
    load([ line ], system: @sap)
    assert_equal 1, Change.where(event: "name_ignored").count
    load([ csv_line("nome" => "Maria Santos", "titulo" => "NF-2") ], system: @sap)
    assert_equal [ "Maria S. Santos", "Maria Santos" ], Change.where(event: "name_ignored").order(:id).pluck(:after)

    # O sistema definido muda o nome.
    load([ csv_line("nome" => "Maria Silva Santos") ])
    assert_equal "Maria Silva Santos", maria.reload.name
  end

  test "R411: enquanto o sistema definido não informou o cliente, os demais podem atualizar" do
    @tenant.setting.update!(customer_record_policy: "defined_system", customer_record_system: @sap)
    load([ csv_line ])
    load([ csv_line("nome" => "Maria Souza") ])
    assert_equal "Maria Souza", customer(MARIA).name

    load([ csv_line("nome" => "Maria S. Santos", "titulo" => "NF-2") ], system: @sap)
    assert_equal "Maria S. Santos", customer(MARIA).name
    load([ csv_line("nome" => "Maria da Silva") ])
    assert_equal "Maria S. Santos", customer(MARIA).name
    assert_equal 1, Change.where(event: "name_ignored", source_system_id: @planilha.id).count
  end

  test "R413: com quem criou primeiro, só o sistema da importação que criou o cliente muda o nome" do
    @tenant.setting.update!(customer_record_policy: "first_creator")
    load([ csv_line ], system: @sap)
    load([ csv_line("nome" => "Maria S. Santos", "titulo" => "NF-2") ])
    assert_equal "Maria da Silva", customer(MARIA).name
    assert_equal [ @sap.id, @planilha.id ], customer(MARIA).source_system_ids

    load([ csv_line("nome" => "Maria Souza") ], system: @sap)
    assert_equal "Maria Souza", customer(MARIA).name
  end

  test "R412: os contatos se somam entre sistemas, cada um com os sistemas que o informaram, e só quem prevalece reativa" do
    @tenant.setting.update!(customer_record_policy: "first_creator", correction_policy: "load")
    load([ csv_line ])
    maria = customer(MARIA)
    phone = maria.contacts.find_by!(kind: "phone")
    assert_equal [ @planilha.id ], phone.source_system_ids
    phone.update!(status: "invalid", reason: "número errado")

    import = load([ csv_line("titulo" => "NF-2", "email" => "maria.santos@exemplo.com.br") ], system: @sap)
    assert_equal [ [ @planilha.id, @sap.id ], "invalid" ], [ phone.reload.source_system_ids, phone.status ]
    added = maria.contacts.find_by!(value: "maria.santos@exemplo.com.br")
    assert_equal [ [ @sap.id ], "valid" ], [ added.source_system_ids, added.status ]
    assert_equal [ @planilha.id ], maria.contacts.find_by!(value: "maria@exemplo.com.br").source_system_ids
    assert_equal 3, maria.contacts.count
    assert_equal @sap.id, Change.find_by!(import_id: import.id, subject_type: "customer_contact", event: "created").source_system_id

    load([ csv_line ])
    assert_equal "valid", phone.reload.status
  end

  test "R414: o batimento só retira títulos do sistema da importação" do
    lines = [ csv_line("titulo" => "NF-1"), csv_line("titulo" => "NF-2") ]
    load(lines)
    load(lines, system: @sap)
    load([ erp_line("T-1", "titulo" => "NF-1") ], system: @erp)

    import = send_file([ csv_line("titulo" => "NF-1") ], system: @sap, mode: :full_sync)
    assert_equal 1, import.summary_data.dig(:to_withdraw, :count)
    confirm(import)

    statuses = ->(system) { Bill.where(tenant: @tenant, source_system: system).order(:number).pluck(:status) }
    assert_equal %w[active withdrawn], statuses.call(@sap)
    assert_equal %w[active active], statuses.call(@planilha)
    assert_equal %w[active], statuses.call(@erp)
    withdrawn = Change.find_by!(import_id: import.id, event: "withdrawn")
    assert_equal @sap.id, withdrawn.source_system_id

    # Em id próprio, o batimento é pelo id do título: mudar o número não retira nada.
    import = load([ erp_line("T-1", "titulo" => "NF-1-A"), erp_line("T-2", "titulo" => "NF-1") ], system: @erp, mode: :full_sync)
    assert_equal 0, import.summary_data.dig(:to_withdraw, :count)
    assert_equal %w[active active], Bill.where(tenant: @tenant, source_system: @erp).order(:external_id).pluck(:status)
    assert_equal %w[active withdrawn], statuses.call(@sap)
  end
end
