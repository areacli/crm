require "test_helper"

# Conferência do impacto e confirmação (08, R154 a R156) e o recálculo por credor (R153).
class SegmentsApplierTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @gestor = users(:joana)
  end

  def proposal(tenant = @alfa) = Segments::Proposal.current(tenant)

  def new_segment(**attributes)
    Segment.new(tenant: @alfa, name: "Varejo PF recente", **attributes).tap { |segment| assert segment.valid?, segment.errors.full_messages.to_sentence }
  end

  test "R154 (critério de aceite): a conferência mostra quantos contratos entram, de onde vêm, e nada muda até confirmar" do
    make_segment(@alfa, "PF", person_type: "person")
    from_pf = make_contract(@alfa, "P1", bills: [ { overdue: 20, cents: 100_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    from_demais = make_contract(@alfa, "P2", bills: [ { overdue: 20, cents: 50_000 } ], customers: [ customer_of(@alfa, CNPJ_A) ])
    recalc(@alfa)

    changed = proposal.with_created(new_segment(min_overdue_days: 1, max_overdue_days: 90)).with_moved(Segments::Proposal::NEW_ID, "up")
    impact = Segments::Impact.new(changed)
    assert_equal 2, impact.total
    row = impact.rows.find { |candidate| changed.name_of(candidate.from_id) == "PF" }
    assert_equal [ "PF", "Varejo PF recente", 1, 100_000 ], [ changed.name_of(row.from_id), changed.name_of(row.to_id), row.contracts, row.balance_cents ]
    assert_equal [ "PF", "Demais" ], [ segment_of(from_pf), segment_of(from_demais) ], "nada mudou antes de confirmar"
  end

  test "R154: confirmar grava, reclassifica na hora, registra e sobe a versão" do
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    version = @alfa.setting.segments_version
    token = proposal.with_created(new_segment(min_overdue_days: 1, max_overdue_days: 90)).token

    Segments::Applier.new(@gestor).confirm(@alfa, token)

    assert_equal "Varejo PF recente", segment_of(contract)
    assert_equal version + 1, @alfa.setting.reload.segments_version
    assert_equal [ "Varejo PF recente", "Demais" ], @alfa.segments.ordered.pluck(:name)
    log = Change.find_by!(subject_type: "segment", event: "created")
    assert_equal [ @gestor, @alfa.id, "Varejo PF recente" ], [ log.user, log.tenant_id, log.after ]
  end

  test "R154: voltar sem confirmar não muda nada" do
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ])
    recalc(@alfa)
    proposal.with_created(new_segment(min_overdue_days: 1)).token
    assert_equal [ "Demais", 1 ], [ segment_of(contract), @alfa.segments.count ]
  end

  test "caso de exceção: conferência velha (dois gestores) é recusada" do
    token = proposal.with_created(new_segment(min_overdue_days: 1)).token
    Segments::Applier.new(@gestor).confirm(@alfa, proposal.with_created(new_segment(name: "Outro", min_overdue_days: 5)).token)
    error = assert_raises(Segments::Refused) { Segments::Applier.new(@gestor).confirm(@alfa, token) }
    assert_match(/os segmentos mudaram depois da sua conferência/i, error.message)
  end

  test "token de outro credor ou adulterado é recusado" do
    token = proposal(@beta).token
    assert_raises(Segments::Refused) { Segments::Applier.new(@gestor).confirm(@alfa, token) }
    assert_raises(Segments::Refused) { Segments::Applier.new(@gestor).confirm(@alfa, "#{token}x") }
  end

  test "R155 (critério de aceite): desativar passa os contratos ao próximo que casar; Demais não desativa; reativar volta" do
    pf = make_segment(@alfa, "PF", person_type: "person")
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    assert_equal "PF", segment_of(contract)

    travel_to(1.day.from_now) { Segments::Applier.new(@gestor).confirm(@alfa, proposal.with_active(pf.id, false).token) }
    assert_equal "Demais", segment_of(contract)
    assert_equal "PF", contract.contract_segments.joins(:segment).order(:id).first.segment.name, "PF continua no histórico"
    catch_all = Segment.catch_all_of(@alfa)
    assert_equal proposal.entries, proposal.with_active(catch_all.id, false).entries, "Demais nunca é desativado"

    travel_to(2.days.from_now) { Segments::Applier.new(@gestor).confirm(@alfa, proposal.with_active(pf.id, true).token) }
    assert_equal "PF", segment_of(contract)
    assert_equal %w[desativado reativado], [ Change.where(event: "deactivated").exists? ? "desativado" : nil, Change.where(event: "reactivated").exists? ? "reativado" : nil ]
  end

  test "R149 e R156: mover para cima muda a ordem e registra antes e depois; Demais não se move" do
    a = make_segment(@alfa, "A", person_type: "person")
    b = make_segment(@alfa, "B", min_overdue_days: 1)
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    assert_equal "A", segment_of(contract)

    moved = proposal.with_moved(b.id, "up")
    assert_equal %w[B A Demais], moved.entries.map { |entry| entry[:name] }
    Segments::Applier.new(@gestor).confirm(@alfa, moved.token)
    assert_equal "B", segment_of(contract)
    log = Change.where(subject_type: "segment", subject_id: b.id, field: "position").last
    assert_equal [ "2", "1" ], [ log.before, log.after ]
    assert_equal proposal.entries, proposal.with_moved(Segment.catch_all_of(@alfa).id, "up").entries, "Demais não se move"
    assert_equal proposal.entries, proposal.with_moved(a.id, "down").entries, "o último dos comuns não desce abaixo do Demais"
  end

  test "R151: mudar a política de produto passa pela conferência e conta os contratos que mudam" do
    make_segment(@alfa, "Cartões", products: [ "cartao" ])
    contract = make_contract(@alfa, "J", bills: [ { overdue: 200, cents: 500_000, product: "Empréstimo" }, { overdue: 30, cents: 30_000, product: "Cartão" } ])
    recalc(@alfa)
    assert_equal "Demais", segment_of(contract)
    impact = Segments::Impact.new(proposal.with_policy("any_bill"))
    assert_equal 1, impact.total
    Segments::Applier.new(@gestor).confirm(@alfa, proposal.with_policy("any_bill").token)
    assert_equal [ "any_bill", "Cartões" ], [ @alfa.setting.reload.segment_product_policy, segment_of(contract) ]
    assert Change.exists?(subject_type: "tenant_setting", field: "segment_product_policy", before: "most_overdue", after: "any_bill")
  end

  test "caso de exceção: contrato misto que muda é contado na conferência" do
    make_segment(@alfa, "PF", person_type: "person")
    ana = customer_of(@alfa, FakeData.cpf(61))
    loja = customer_of(@alfa, CNPJ_A)
    make_contract(@alfa, "MIX", bills: [ {} ], customers: [ ana, loja ], roles: { ana.id => %w[financial_responsible], loja.id => %w[financial_responsible] })
    recalc(@alfa)
    impact = Segments::Impact.new(proposal.with_active(@alfa.segments.find_by!(name: "PF").id, false))
    assert_equal 0, impact.total
    other = proposal.with_created(Segment.new(tenant: @alfa, name: "Mistos", person_type: "mixed").tap(&:valid?))
    assert_equal 1, Segments::Impact.new(other).mixed
  end

  test "segmento que não pega ninguém é aceito e a conferência diz que nenhum contrato muda" do
    make_contract(@alfa, "P", bills: [ { overdue: 5 } ])
    recalc(@alfa)
    assert_equal 0, Segments::Impact.new(proposal.with_created(new_segment(min_overdue_days: 9999))).total
  end

  test "caso de exceção: critérios impossíveis, nome repetido e Demais com critérios são recusados com a mensagem do campo" do
    make_segment(@alfa, "Um")
    {
      { min_overdue_days: 10, max_overdue_days: 5 } => :max_overdue_days, { min_balance_cents: 500, max_balance_cents: 100 } => :max_balance_cents,
      { min_overdue_bills: 5, max_overdue_bills: 2 } => :max_overdue_bills, { max_overdue_percent: 101 } => :max_overdue_percent,
      { min_customers: 3, max_customers: 1 } => :max_customers, { min_age_days: 9, max_age_days: 1 } => :max_age_days
    }.each do |attributes, field|
      segment = Segment.new(tenant: @alfa, name: "Impossível", **attributes)
      assert_not segment.valid?
      assert segment.errors[field].any?, field.to_s
    end
    assert_not Segment.new(tenant: @alfa, name: " UM ").valid?
    assert Segment.new(tenant: @beta, name: "Um").valid?, "o mesmo nome em outro credor é aceito"
    assert_not Segment.new(tenant: @alfa, name: "Demais", catch_all: true, min_overdue_days: 1).valid?
  end

  test "R153 (critério de aceite): a falha de um credor não impede o outro e fica no registro dele" do
    make_segment(@beta, "Longo", min_overdue_days: 100)
    beta = make_contract(@beta, "B", bills: [ { overdue: 200 } ])
    make_contract(@alfa, "A", bills: [ { overdue: 5 } ])
    Segments::Calculator.class_eval { alias_method :original_sql, :sql }
    Segments::Calculator.define_method(:sql) { raise ActiveRecord::StatementInvalid, "falha simulada" if @tenant.name == "Escola Alfa"; original_sql }
    begin
      # Um aviso do recálculo dos segmentos e outro da abertura do recálculo dos valores atualizados (09), que o segue.
      assert_broadcasts(SegmentsChannel.broadcasting_for(@alfa), 2) do
        SegmentsDispatchJob.perform_now
        [ @alfa, @beta ].each { |tenant| SegmentsRecalculationJob.perform_now(tenant) }
      end
    ensure
      Segments::Calculator.class_eval { alias_method :sql, :original_sql }
    end
    assert_equal "Longo", segment_of(beta)
    assert TaskRun.where(tenant: @alfa, name: "segments_recalculation").last.failed?
    assert TaskRun.where(tenant: @beta, name: "segments_recalculation").last.succeeded?
  end

  test "R153: confirmar uma carga de carteira enfileira o recálculo do credor" do
    include_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    csv = write_csv([ csv_line("documento" => FakeData.cpf(71), "nome" => "Pessoa", "contrato" => "K", "titulo" => "T1", "vencimento" => (Date.current - 20).strftime("%d/%m/%Y"), "valor" => "100,00") ])
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: @gestor, file: csv, mode: :incremental, original_name: "c.csv")
    Portfolio::ImportChecker.new.run(import.reload)
    Portfolio::ImportService.new.confirm(import.reload)
    ConfirmImportJob.perform_now(import.reload)
    assert_enqueued_with(job: SegmentsRecalculationJob, args: [ @alfa, import ])
  ensure
    ActiveJob::Base.queue_adapter = include_adapter
  end
end
