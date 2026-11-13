require "test_helper"

# Pagamentos e estornos por sistema (17, R416 a R419): a linha declara o sistema na coluna `sistema`, o título é procurado dentro dele (pelo id, em sistema de id
# próprio, ou por documento e número), o pai do pagamento é o sistema da linha, o pendente só é reavaliado no sistema dele e muda de sistema quando é reenviado
# com outro, e o instrumento pago vale para o título a que foi emitido.
class Payments::SystemPaymentsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  ANA = "111.444.777-35".freeze
  HEADER = (PaymentsHelper::PAYMENT_HEADER + %w[sistema id_titulo]).freeze
  REVERSALS = (PaymentsHelper::REVERSAL_HEADER + %w[sistema]).freeze
  REQUIRED = "sistema obrigatório: o credor tem mais de um sistema".freeze

  setup do
    @tenant = tenants(:alfa)
    @user = users(:joana)
    @manager = SourceSystems::Manager.new(@user)
    @sap = @manager.create(tenant: @tenant, name: "SAP", key_kind: "natural")
    @erp = @manager.create(tenant: @tenant, name: "ERP", key_kind: "own_id")
    @crm = source_systems(:alfa_crm)
  end

  # Título de um sistema: em chave natural vale o número; em id próprio, `external_id`.
  def system_bill(system, number:, external_id: nil, document: MARIA, amount_cents: 100_000)
    customer = Customer.find_or_create_by!(tenant: @tenant, document: Document.normalize(document)) { |record| record.name = "Cliente #{document}" }
    contract = Contract.find_or_create_by!(tenant: @tenant, source_system: system, code: "CT-#{system.name}-#{customer.id}") do |record|
      record.external_id = "K-#{customer.id}" if system.key_own_id?
    end
    ContractCustomer.find_or_create_by!(contract: contract, customer: customer)
    Bill.create!(tenant: @tenant, contract: contract, customer: customer, number: number, external_id: external_id, due_date: Date.current - 30, amount_cents: amount_cents, status: :active)
  end

  def check(lines, kind: "payments")
    header = kind == "payments" ? HEADER : REVERSALS
    import = Portfolio::ImportService.new.start(tenant: @tenant, user: @user, file: write_csv(lines, header: header), mode: :incremental, original_name: "#{kind}.csv", kind: kind)
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def pay(lines, **options) = confirm_import(check(lines, **options))

  def reasons(import) = import.rejections.order(:line).pluck(:line, :reason).to_h

  def payment(identifier) = Payment.find_by!(tenant: @tenant, identifier: identifier)

  test "R416, R418: cada linha declara o sistema, sem diferenciar maiúsculas; o pai do pagamento é o sistema da linha e a linha sem sistema é recusada" do
    make_channel(@tenant)
    nf1 = system_bill(@sap, number: "NF-1")
    t77 = system_bill(@erp, number: "NF-9", external_id: "T-77")
    import = check([ payment_line(identificador: "PIX-1", sistema: "SAP"),
                     payment_line(identificador: "PIX-2", sistema: "erp", titulo: "", id_titulo: "T-77"),
                     payment_line(identificador: "PIX-3"),
                     payment_line(identificador: "PIX-4", sistema: "Totvs") ])

    assert_equal({ 4 => REQUIRED, 5 => "sistema desconhecido: Totvs" }, reasons(import))
    assert_equal [ 4, 2, 2 ], import.summary_data.values_at(:lines, :valid, :rejected)

    confirm_import(import)
    assert_equal [ "applied", @sap, nf1 ], [ payment("PIX-1").status, payment("PIX-1").source_system, payment("PIX-1").bill ]
    # O pagamento só com o id guarda o id e o número do título achado.
    assert_equal [ "applied", @erp, t77, "T-77", "NF-9" ], payment("PIX-2").then { |p| [ p.status, p.source_system, p.bill, p.external_bill_id, p.bill_number ] }
    assert_predicate nf1.reload, :paid?
    assert_predicate t77.reload, :paid?
    assert_equal 2, Payment.count
  end

  test "R416: a linha com número de acordo dispensa o sistema, é aplicada à parcela e tem o CRM como pai" do
    travel_day(AGREEMENT_DAY)
    _customer, _nf1, _nf2, agreement = accepted_agreement(@tenant)
    day = Date.new(2026, 11, 4)
    travel_day(day)
    import = pay([ pay_line("ACD-000001-00", day, 34_366, id: "PIX-A"), pay_line("NF-1", day, 10_000, id: "PIX-B") ])

    assert_equal({ 3 => REQUIRED }, reasons(import))
    assert_predicate agreement.reload, :state_active_on_time?
    assert_equal [ "applied", @crm ], [ payment("PIX-A").status, payment("PIX-A").source_system ]
    assert_predicate Bill.find_by!(number: "ACD-000001-00"), :paid?
  ensure
    travel_back
  end

  test "R416, R398: o sistema pausado recusa a linha; com um só sistema a coluna é ignorada" do
    make_channel(@tenant)
    system_bill(@sap, number: "NF-1")
    @manager.pause(@sap)
    assert_equal({ 2 => "o sistema SAP está pausado" }, reasons(check([ payment_line(sistema: "SAP") ])))

    # A Beta só tem o Planilha: o que vier na coluna não é lido, e a linha é dele.
    beta = Payments::Systems.new(tenants(:beta).id)
    assert_not_predicate beta, :multiple?
    assert_equal [ source_systems(:beta_planilha), nil ], beta.of_line("Qualquer", internal: false)
    assert_equal [ source_systems(:beta_planilha), nil ], beta.of_line("", internal: false)
    assert_equal [ nil, nil ], beta.declared("Qualquer")
    assert_equal source_systems(:beta_crm), beta.parent(nil)
  end

  test "R417: o id que não existe no sistema não cai para o número (fica pendente); em chave natural a coluna de id é ignorada" do
    make_channel(@tenant)
    t77 = system_bill(@erp, number: "NF-9", external_id: "T-77")
    nf1 = system_bill(@sap, number: "NF-1")
    pay([ payment_line(identificador: "PIX-1", sistema: "ERP", titulo: "NF-9", id_titulo: "T-99"),
          payment_line(identificador: "PIX-2", sistema: "SAP", titulo: "NF-1", id_titulo: "T-77") ])

    assert_equal [ "pending", @erp, "T-99" ], payment("PIX-1").then { |p| [ p.status, p.source_system, p.external_bill_id ] }
    assert_predicate t77.reload, :active?
    assert_equal [ "applied", nf1, nil ], payment("PIX-2").then { |p| [ p.status, p.bill, p.external_bill_id ] }
  end

  test "R417: o título é procurado só no sistema da linha; o mesmo número em outro sistema não entra na conta" do
    make_channel(@tenant)
    planilha = make_bill(@tenant, number: "NF-100")
    sap = system_bill(@sap, number: "NF-100")
    pay([ payment_line(identificador: "PIX-1", sistema: "SAP", titulo: "NF-100") ])

    assert_equal sap, payment("PIX-1").bill
    assert_predicate sap.reload, :paid?
    assert_predicate planilha.reload, :active?
  end

  test "R417a: pagador terceiro acha o título pelo número único naquele sistema; com mais de um, fica pendente" do
    make_channel(@tenant)
    make_bill(@tenant, number: "NF-5")
    nf5 = system_bill(@sap, number: "NF-5")
    system_bill(@sap, number: "NF-6")
    system_bill(@sap, number: "NF-6", document: JOAO)
    pay([ payment_line(identificador: "PIX-1", sistema: "SAP", titulo: "NF-5", documento: ANA),
          payment_line(identificador: "PIX-2", sistema: "SAP", titulo: "NF-6", documento: ANA) ])

    assert_equal [ "applied", nf5 ], [ payment("PIX-1").status, payment("PIX-1").bill ]
    assert_equal [ "pending", nil, @sap ], payment("PIX-2").then { |p| [ p.status, p.bill, p.source_system ] }
  end

  test "R418: o pendente só é reavaliado no sistema dele; reenviado com o mesmo identificador e outro sistema, troca de sistema e é aplicado" do
    make_channel(@tenant)
    oracle = @manager.create(tenant: @tenant, name: "Oracle", key_kind: "natural")
    nf100 = system_bill(oracle, number: "NF-100")
    system_bill(@sap, number: "NF-1")
    pay([ payment_line(identificador: "PIX-7", sistema: "SAP", titulo: "NF-100") ])
    assert_equal [ "pending", @sap ], [ payment("PIX-7").status, payment("PIX-7").source_system ]

    # Outra importação reavalia os pendentes: o título só existe no Oracle, e o pendente é do SAP.
    pay([ payment_line(identificador: "PIX-8", sistema: "SAP", titulo: "NF-1") ])
    assert_equal "pending", payment("PIX-7").status
    assert_predicate nf100.reload, :active?

    # O mesmo sistema é só um pagamento já registrado.
    again = check([ payment_line(identificador: "PIX-7", sistema: "SAP", titulo: "NF-100") ])
    assert_equal [ "pagamento já registrado, ignorado" ], again.rejections.pluck(:reason)
    Portfolio::ImportService.new.discard(again)

    resent = check([ payment_line(identificador: "PIX-7", sistema: "Oracle", titulo: "NF-100") ])
    assert_equal [ 1, 0, 0, 1 ], resent.summary_data.values_at(:lines, :valid, :rejected, :repointed)
    assert_equal 0, resent.rejections.count
    assert_equal [ "pending", @sap ], [ payment("PIX-7").status, payment("PIX-7").source_system ], "a conferência não muda o pagamento"

    confirm_import(resent)
    assert_equal [ "applied", oracle, nf100 ], payment("PIX-7").then { |p| [ p.status, p.source_system, p.bill ] }
    assert_predicate nf100.reload, :paid?
    assert_equal 2, Payment.count, "o reenvio não cria outro pagamento (R419)"
    change = Change.find_by!(subject_type: "payment", subject_id: payment("PIX-7").id, event: "system_changed")
    assert_equal [ "SAP", "Oracle", oracle.id, resent.id ], [ change.before, change.after, change.source_system_id, change.import_id ]
  end

  test "R418: o pendente reenviado para um sistema que também não tem o título troca de sistema e continua pendente" do
    make_channel(@tenant)
    pay([ payment_line(identificador: "PIX-7", sistema: "SAP", titulo: "NF-100") ])
    pay([ payment_line(identificador: "PIX-7", sistema: "ERP", titulo: "NF-100", id_titulo: "T-100") ])

    assert_equal [ "pending", @erp, "T-100", "NF-100" ], payment("PIX-7").then { |p| [ p.status, p.source_system, p.external_bill_id, p.bill_number ] }
    assert_equal 1, Payment.count
  end

  test "R417b: o instrumento pago baixa o título a que foi emitido, com o CRM como pai, mesmo com outro título de mesmo número em outro sistema" do
    t77 = system_bill(@erp, number: "NF-100", external_id: "T-77")
    other = system_bill(@sap, number: "NF-100")
    instrument = emit(@tenant, t77.customer, "boleto", 100_000, object: t77)
    fake_paid!(instrument)

    assert_equal :applied, Payments::InstrumentSync.new.call(instrument).kind
    assert_predicate t77.reload, :paid?
    assert_predicate other.reload, :active?
    assert_equal [ "applied", @crm, t77 ], Payment.sole.then { |p| [ p.status, p.source_system, p.bill ] }
  end

  test "R416, estornos: o sistema da linha é o do pagamento estornado; vazio, de outro sistema ou desconhecido, a linha é recusada" do
    make_channel(@tenant)
    system_bill(@sap, number: "NF-1")
    pay([ payment_line(identificador: "PIX-1", sistema: "SAP") ])

    import = check([ reversal_line(identificador_estorno: "EST-1", sistema: "ERP"), reversal_line(identificador_estorno: "EST-2"),
                     reversal_line(identificador_estorno: "EST-3", sistema: "Totvs"), reversal_line(identificador_estorno: "EST-4", sistema: "sap") ], kind: "reversals")
    assert_equal({ 2 => "o pagamento é de outro sistema: SAP", 3 => REQUIRED, 4 => "sistema desconhecido: Totvs" }, reasons(import))

    confirm_import(import)
    assert_equal [ "EST-4" ], PaymentReversal.pluck(:identifier)
    assert_equal 30_000, payment("PIX-1").reversed_cents
  end

  test "estornos: o pagamento cujo pai é o CRM se estorna sem sistema, e o de sistema pausado não recebe estorno" do
    make_channel(@tenant)
    system_bill(@sap, number: "NF-1")
    system_bill(@sap, number: "NF-2")
    pay([ payment_line(identificador: "PIX-1", sistema: "SAP"), payment_line(identificador: "PIX-2", sistema: "SAP", titulo: "NF-2") ])
    # Pagamento do CRM, como o de um instrumento emitido por ele (R417b).
    payment("PIX-2").update_columns(source_system_id: @crm.id)
    @manager.pause(@sap)

    import = check([ reversal_line(identificador_estorno: "EST-1"), reversal_line(identificador_pagamento: "PIX-2", identificador_estorno: "EST-2") ], kind: "reversals")
    assert_equal({ 2 => "o sistema SAP está pausado" }, reasons(import))
    confirm_import(import)
    assert_equal [ "EST-2" ], PaymentReversal.pluck(:identifier)
  end

  test "R417: o resolvedor de títulos responde por lote, com cada linha no sistema dela" do
    planilha = make_bill(@tenant, number: "NF-1")
    sap = system_bill(@sap, number: "NF-1")
    erp = system_bill(@erp, number: "NF-1", external_id: "T-1")
    key = ->(line, **given) { Payments::BillResolver::Key.new(**{ line: line, number: "NF-1", document: Document.normalize(MARIA), system_id: nil, external_id: nil, target_id: nil }.merge(given)) }

    found = Payments::BillResolver.new(@tenant.id).resolve([
      key.call(1, system_id: @sap.id), key.call(2, system_id: @erp.id, external_id: "T-1", number: nil), key.call(3, system_id: source_systems(:alfa_planilha).id),
      key.call(4, system_id: @erp.id, external_id: "T-404"), key.call(5, target_id: erp.id), key.call(6, system_id: @sap.id, number: "NF-404")
    ])
    assert_equal({ 1 => sap.id, 2 => erp.id, 3 => planilha.id, 5 => erp.id }, found)
  end

  test "modelo de planilha: `sistema` com sistema remoto, `id_titulo` com sistema de id próprio, e nada disso para quem só tem o Planilha" do
    assert_equal PaymentsHelper::PAYMENT_HEADER, Payments::SheetModel.columns("payments")
    assert_equal PaymentsHelper::PAYMENT_HEADER + %w[sistema], Payments::SheetModel.columns("payments", remote: [ @sap ])
    assert_equal HEADER, Payments::SheetModel.columns("payments", remote: [ @sap, @erp ])
    assert_equal REVERSALS, Payments::SheetModel.columns("reversals", remote: [ @sap, @erp ])
    assert_equal PaymentsHelper::REVERSAL_HEADER, Payments::SheetModel.columns("reversals")
    assert_equal HEADER.join(";"), Payments::SheetModel.csv("payments", remote: [ @sap, @erp ]).lines.first.strip.delete_prefix("﻿")
  end

  test "R423: a mudança de pagamento e de estorno guarda o sistema do pagamento; a do pagamento cujo pai é o CRM fica sem sistema" do
    make_channel(@tenant)
    nf1 = system_bill(@sap, number: "NF-1")
    t77 = system_bill(@erp, number: "NF-9", external_id: "T-77")
    # O PIX-1 paga a mais: a sobra vira crédito do contrato, também com o sistema do pagamento.
    pay([ payment_line(identificador: "PIX-1", sistema: "SAP", valor: "1.200,00"), payment_line(identificador: "PIX-2", sistema: "ERP", titulo: "", id_titulo: "T-77") ])
    systems = ->(subject, event) { Change.where(subject_type: subject.class.name.underscore, subject_id: subject.id, event: event).pluck(:source_system_id) }

    assert_equal [ @sap.id ], systems.call(nf1, "payment_applied")
    assert_equal [ @erp.id ], systems.call(t77, "payment_applied")
    assert_equal [ @sap.id ], systems.call(nf1.contract, "credit_added")

    payment("PIX-2").update_columns(source_system_id: @crm.id)
    pay([ reversal_line(identificador_estorno: "EST-1", sistema: "SAP", valor: "1.200,00"), reversal_line(identificador_pagamento: "PIX-2", identificador_estorno: "EST-2") ], kind: "reversals")

    assert_equal [ @sap.id ], systems.call(nf1, "payment_reversed")
    assert_equal [ nil ], systems.call(t77, "payment_reversed")
  end
end
