require "test_helper"

# Sistemas do credor (17, R396 a R399) e o sistema pai de contrato, título e pagamento (R403, R404, R417).
class SourceSystemTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @crm = source_systems(:alfa_crm)
    @sheet = source_systems(:alfa_planilha)
    @erp = SourceSystem.create!(tenant: @alfa, name: "ERP Escolar", key_kind: "own_id")
  end

  def import_into(system) = Import.create!(tenant: @alfa, user: users(:joana), source_system: system, mode: :incremental, status: :confirmed, original_name: "erp.csv", size_bytes: 10)

  test "R397: o nome é único no credor, sem diferença de maiúsculas, e livre entre credores" do
    repeated = SourceSystem.new(tenant: @alfa, name: "  erp   escolar ")

    assert_not repeated.valid?
    assert_includes repeated.errors[:name], "já está em uso"
    assert SourceSystem.new(tenant: tenants(:beta), name: "ERP Escolar").valid?
    assert_raises(ActiveRecord::RecordNotUnique) { SourceSystem.insert_all!([ { tenant_id: @alfa.id, name: "ERP ESCOLAR" } ]) }
  end

  test "R397: sistema novo é remoto, de chave natural e ativo, salvo se disser outra coisa" do
    system = SourceSystem.create!(tenant: @alfa, name: "Faturamento")

    assert_equal %w[remote natural active], [ system.role, system.key_kind, system.status ]
    assert_predicate @erp, :key_own_id?
  end

  test "R396: o CRM não é editado, pausado nem excluído, e o banco recusa um CRM pausado" do
    assert_not @crm.update(name: "Outro nome")
    assert_includes @crm.errors[:base], "o sistema CRM não pode ser alterado"
    assert_not @crm.reload.update(status: "paused")
    assert_not @crm.reload.destroy
    assert_includes @crm.errors[:base], "o sistema CRM não pode ser excluído"
    assert_raises(ActiveRecord::StatementInvalid) { SourceSystem.where(id: @crm.id).update_all(status: "paused") }
  end

  test "R396: o Planilha pode ser renomeado e pausado, mas não excluído, e segue de chave natural" do
    assert @sheet.update(name: "Planilha do financeiro", status: "paused")
    assert_not @sheet.update(key_kind: "own_id")
    assert_not @sheet.reload.destroy
    assert_includes @sheet.errors[:base], "o sistema Planilha do financeiro não pode ser excluído"
  end

  test "R396: um CRM e um padrão por credor, pelo banco" do
    assert_raises(ActiveRecord::RecordNotUnique) { SourceSystem.create!(tenant: @alfa, name: "CRM 2", role: "crm") }
    assert_raises(ActiveRecord::RecordNotUnique) { SourceSystem.create!(tenant: @alfa, name: "Planilha 2", role: "default") }
    assert_not @erp.update(role: "default")
    assert_includes @erp.errors[:role], "não muda"
  end

  test "R397 e R399: antes da primeira importação o tipo de chave muda e o sistema pode ser excluído; depois, não" do
    assert @erp.update(key_kind: "natural")
    assert @erp.update(key_kind: "own_id")
    import_into(@erp)

    assert_not @erp.update(key_kind: "natural")
    assert_includes @erp.errors[:key_kind], "não muda depois da primeira importação"
    assert_not @erp.reload.destroy
    assert_includes @erp.errors[:base], "sistema com importação não pode ser excluído, só pausado"
    assert @erp.reload.update(status: "paused", name: "ERP antigo")

    assert SourceSystem.create!(tenant: @alfa, name: "Sem uso").destroy
  end

  test "os que recebem importação são todos, menos o CRM" do
    assert_equal [ @erp.id, @sheet.id ].sort, SourceSystem.where(tenant: @alfa).receiving.pluck(:id).sort
    assert_equal @crm, SourceSystem.crm_of(@alfa.id)
    assert_equal @sheet, SourceSystem.default_of(@alfa.id)
  end

  test "R403: contrato sem sistema informado é do padrão do credor; o título comum segue o contrato" do
    bill = make_bill(@alfa)
    contract = Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-ERP", external_id: "9001")
    ContractCustomer.create!(contract: contract, customer: bill.customer)
    remote = Bill.create!(tenant: @alfa, contract: contract, customer: bill.customer, number: "NF-2", due_date: Date.current, amount_cents: 1_000)

    assert_equal @sheet, bill.contract.source_system
    assert_equal @sheet, bill.source_system
    assert_equal @erp, remote.source_system
  end

  test "R403: título que o CRM cria (acordo, quebra, estorno) é do sistema CRM, em qualquer contrato" do
    travel_day(AGREEMENT_DAY)
    _customer, nf1, _nf2, agreement = accepted_agreement(@alfa)
    remote = Bill.new(tenant: @alfa, contract: Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-ERP"), customer: nf1.customer, kind: "break", number: "Q-1")
    remote.valid?

    assert_operator agreement.titles.count, :>, 1
    assert_equal [ @crm.id ], agreement.titles.pluck(:source_system_id).uniq
    assert_equal @sheet, nf1.reload.source_system
    assert_equal @crm, remote.source_system, "também em contrato de outro sistema"
  ensure
    travel_back
  end

  test "R403: o sistema pai do contrato e do título não muda depois de criado" do
    bill = make_bill(@alfa)

    assert_raises(ActiveRecord::ReadonlyAttributeError) { bill.update!(source_system: @erp) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { bill.contract.update!(source_system: @erp) }
    assert_equal @sheet.id, bill.reload.source_system_id
  end

  test "R404: o mesmo número do mesmo cliente cabe em dois sistemas e é único dentro de cada um" do
    bill = make_bill(@alfa, number: "NF-1")
    contract = Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-1")
    other = Bill.create!(tenant: @alfa, contract: contract, customer: bill.customer, number: "NF-1", due_date: Date.current, amount_cents: 1_000)

    assert_equal @erp, other.source_system
    assert_raises(ActiveRecord::RecordNotUnique) do
      Bill.create!(tenant: @alfa, contract: bill.contract, customer: bill.customer, number: "NF-1", due_date: Date.current, amount_cents: 1_000)
    end
  end

  test "R404: o código do contrato é único por sistema; o id remoto também, e libera o código repetido" do
    Contract.create!(tenant: @alfa, code: "CT-9")
    Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-9", external_id: "77")
    Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-9", external_id: "78")

    assert_raises(ActiveRecord::RecordNotUnique) { Contract.create!(tenant: @alfa, code: "CT-9") }
    assert_raises(ActiveRecord::RecordNotUnique) { Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-10", external_id: "77") }
    assert_equal 3, Contract.where(tenant: @alfa, code: "CT-9").count
  end

  test "R406: em sistema de id próprio o título é único pelo id remoto, e o número pode repetir" do
    bill = make_bill(@alfa)
    contract = Contract.create!(tenant: @alfa, source_system: @erp, code: "CT-ERP", external_id: "9001")
    attributes = { tenant: @alfa, contract: contract, customer: bill.customer, number: "MENSALIDADE", due_date: Date.current, amount_cents: 1_000 }
    Bill.create!(**attributes, external_id: "T-1")
    Bill.create!(**attributes, external_id: "T-2")

    assert_raises(ActiveRecord::RecordNotUnique) { Bill.create!(**attributes, number: "OUTRO", external_id: "T-1") }
  end

  test "R417: pagamento sem sistema informado é do padrão do credor; o uso de crédito do contrato é do CRM" do
    bill = make_bill(@alfa)
    attributes = { tenant: @alfa, document: bill.customer.document, bill_number: bill.number, bill: bill, paid_on: Date.current, amount_cents: 1_000, payment_method: "pix", status: "pending" }
    imported = Payment.create!(**attributes, channel: make_channel(@alfa), identifier: "PIX-1")
    credit = Payment.create!(**attributes, channel: Agreements::CreditUse.channel_for(@alfa), identifier: "CRED-1")

    assert_equal @sheet, imported.source_system
    assert_equal @crm, credit.source_system
  end

  test "R416: com um só sistema além do CRM, o pagamento que a importação grava é dele, sem a coluna `sistema`" do
    @erp.destroy!
    make_channel(@alfa)
    make_bill(@alfa)
    run_payments_import([ payment_line ], confirm: true)

    assert_equal [ @sheet.id ], Payment.where(tenant: @alfa).pluck(:source_system_id)
  end

  test "R400: a importação de carteira assume o sistema padrão; a de pagamentos não tem sistema" do
    attributes = { tenant: @alfa, user: users(:joana), mode: :incremental, status: :confirmed, original_name: "arquivo.csv", size_bytes: 10 }

    assert_equal @sheet, Import.create!(**attributes, kind: :portfolio).source_system
    assert_nil Import.create!(**attributes, kind: :payments).source_system
    assert_equal @erp, import_into(@erp).source_system
  end

  test "R403: a carga de carteira grava contratos e títulos no sistema da importação" do
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "carteira.csv",
                                                file: write_csv([ csv_line ]))
    perform_enqueued_jobs(only: CheckImportJob)
    confirm_import(import.reload)

    assert_equal [ @sheet.id ], Contract.where(tenant: @alfa).pluck(:source_system_id)
    assert_equal [ @sheet.id ], Bill.where(tenant: @alfa).pluck(:source_system_id)
    assert_equal [ nil ], Bill.where(tenant: @alfa).pluck(:external_id)
  end

  test "decisão 0021: a confirmação lê o sistema da importação uma vez, não a cada contrato ou título" do
    lines = (1..4).map { |n| csv_line(contrato: "CT-#{n}", titulo: "NF-#{n}") }
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "carteira.csv", file: write_csv(lines))
    perform_enqueued_jobs(only: CheckImportJob)
    reads = []
    counter = ->(*, payload) { reads << payload[:sql] if payload[:sql].match?(/FROM "source_systems"/) }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { confirm_import(import.reload) }

    assert_equal 4, Bill.where(tenant: @alfa, source_system: @sheet).count
    assert_operator reads.size, :<=, 1, reads.join("\n")
  end

  test "R410: a política Cadastro entre sistemas nasce em último a enviar, e sistema definido exige o sistema" do
    setting = @alfa.setting

    assert_predicate setting, :customer_record_policy_last_sender?
    assert_not setting.update(customer_record_policy: "defined_system")
    assert setting.update(customer_record_policy: "defined_system", customer_record_system: @erp)
    assert_not setting.update(customer_record_policy: "first_creator")
    assert setting.update(customer_record_policy: "first_creator", customer_record_system: nil)
    assert_not @alfa.setting.update(customer_record_policy: "qualquer")
  end

  test "permissão 23, configurar integração: o Gestor tem, o Operador não" do
    assert_includes Permission::ALL, "configure_integration"
    assert_equal 23, Permission.number("configure_integration")
    assert_not_includes Permission::OPERATOR, "configure_integration"
    assert_includes profiles(:alfa_manager).permissions, "configure_integration"
  end
end
