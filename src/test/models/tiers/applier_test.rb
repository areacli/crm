require "test_helper"

# Enquadramento financeiro (13, R265 a R274): o primeiro item que casa, a conferência do impacto em segundo plano, a confirmação, a conferência
# velha, o item novo com regras copiadas, tirar e mover, o segmento usado que muda e o histórico.
class TiersApplierTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @gestor = users(:joana)
  end

  def proposal(tenant = @alfa) = Tiers::Proposal.current(tenant)

  def confirm(changed) = Tiers::Applier.new(@gestor).confirm(@alfa, changed.token)

  test "R267, revisão 6: vale o primeiro item que casa; quem não casa fica no Demais; todo contrato é enquadrado" do
    make_tier(@alfa, "Varejo PF recente", person_type: "person", min_overdue_days: 1, max_overdue_days: 90, max_balance_cents: 500_000)
    make_tier(@alfa, "PF", person_type: "person")
    maria = make_contract(@alfa, "C-MARIA", bills: [ { overdue: 40, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(1)) ])
    jose = make_contract(@alfa, "C-JOSE", bills: [ { overdue: 200, cents: 90_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(2)) ])
    loja = make_contract(@alfa, "C-LOJA", bills: [ { overdue: 10, cents: 30_000 } ], customers: [ customer_of(@alfa, CNPJ_A) ])
    paid = make_contract(@alfa, "C-PAGO", bills: [ { overdue: 10 } ])
    paid.bills.update_all(status: "paid")
    recalc(@alfa)
    assert_equal [ "Varejo PF recente", "PF", "Demais" ], [ tier_of(maria), tier_of(jose), tier_of(loja) ]
    assert_not_nil tier_of(paid), "sem regra de entrada: o contrato sem título em cobrança também é enquadrado"
  end

  test "R272: a conferência conta quem entra e sai e de onde vem; nada muda até confirmar" do
    make_tier(@alfa, "PF", person_type: "person")
    from_pf = make_contract(@alfa, "P1", bills: [ { overdue: 20, cents: 100_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    make_contract(@alfa, "P2", bills: [ { overdue: 20, cents: 50_000 } ], customers: [ customer_of(@alfa, CNPJ_A) ])
    recalc(@alfa)
    recent = make_segment(@alfa, "Recentes", min_overdue_days: 1, max_overdue_days: 90)
    first = proposal.entries.first[:id]
    changed = proposal.with_included(recent, before_id: first, copy_from_id: Tier.catch_all_of(@alfa).id)
    impact = Tiers::Impact.new(changed)
    assert_equal 2, impact.total
    row = impact.rows.find { |candidate| changed.name_of(candidate.from_id) == "PF" }
    assert_equal [ "PF", "Recentes", 1, 100_000 ], [ changed.name_of(row.from_id), changed.name_of(row.to_id), row.contracts, row.balance_cents ]
    assert_equal "PF", tier_of(from_pf), "nada mudou antes de confirmar"
  end

  test "R272, revisão 3: a conferência roda em segundo plano, guarda o resultado e avisa pelo WebSocket" do
    make_contract(@alfa, "P1", bills: [ { overdue: 20, cents: 100_000 } ])
    recalc(@alfa)
    changed = proposal.with_included(make_segment(@alfa, "Todos"), before_id: nil, copy_from_id: nil)
    id = Tiers::Review.start(changed, back: "/x", changes: [])
    assert_equal "running", Tiers::Review.fetch(id)["status"]
    assert_enqueued_with(job: TierReviewJob, args: [ id ])
    assert_broadcasts(SegmentsChannel.broadcasting_for(@alfa), 1) { perform_enqueued_jobs(only: TierReviewJob) }
    review = Tiers::Review.fetch(id)
    assert_equal [ "done", 1 ], [ review["status"], review["total"] ]
    assert_equal({ "from" => "Demais", "to" => "Todos", "contracts" => 1, "balance_cents" => 100_000 }, review["moves"].first)
  end

  test "R266, R272: confirmar inclui o item, reclassifica na hora, registra e sobe a versão; o item novo copia as regras escolhidas (SG15)" do
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    source = make_tier(@alfa, "Origem", [ { "path" => "overdue_days", "op" => "gt", "value" => 999 } ], fine_pct: 2, promise_max_days: 45, agreement_max_installments: 6)
    PromiseLimit.where(tier: source, profile: profiles(:alfa_operator)).update_all(max_days: 12)
    recalc(@alfa)
    version = @alfa.setting.tiers_version
    segment = make_segment(@alfa, "Recentes", min_overdue_days: 1, max_overdue_days: 90)
    confirm(proposal.with_included(segment, before_id: source.id, copy_from_id: source.id))

    tier = Tier.find_by!(segment: segment)
    assert_equal "Recentes", tier_of(contract)
    assert_equal [ 2, 45, 6 ], [ tier.fine_pct.to_i, tier.promise_max_days, tier.agreement_max_installments ]
    assert_equal 12, PromiseLimit.find_by!(tier: tier, profile: profiles(:alfa_operator)).max_days
    assert_equal [ "Recentes", "Origem", "Demais" ], @alfa.tiers.financial.active_ones.or(@alfa.tiers.where(catch_all: true)).ordered.map(&:name)
    assert_equal version + 1, @alfa.setting.reload.tiers_version
    assert Change.exists?(subject_type: "tier", subject_id: tier.id, event: "created", user: @gestor, after: "Recentes")
  end

  test "caso de exceção: a conferência velha (dois gestores) é recusada" do
    token = proposal.with_included(make_segment(@alfa, "A", min_overdue_days: 1), before_id: nil, copy_from_id: nil).token
    confirm(proposal.with_included(make_segment(@alfa, "B", min_overdue_days: 5), before_id: nil, copy_from_id: nil))
    error = assert_raises(Tiers::Refused) { Tiers::Applier.new(@gestor).confirm(@alfa, token) }
    assert_match(/o enquadramento mudou depois da sua conferência/i, error.message)
    assert_raises(Tiers::Refused) { Tiers::Applier.new(@gestor).confirm(@alfa, "#{token}x") }
    assert_raises(Tiers::Refused) { Tiers::Applier.new(@gestor).confirm(@beta, proposal.token) }
  end

  test "R266: tirar do enquadramento deixa o item inativo e manda os contratos para o próximo; o histórico guarda o item" do
    pf = make_tier(@alfa, "PF", person_type: "person")
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    travel_to(1.day.from_now) { confirm(proposal.with_removed(pf.id)) }
    assert_equal [ "Demais", false ], [ tier_of(contract), pf.reload.active ]
    assert_equal [ "PF", "Demais" ], contract.contract_tiers.order(:since).map { |entry| entry.tier.name }
    assert_equal proposal.entries, proposal.with_removed(Tier.catch_all_of(@alfa).id).entries, "Demais não sai"
  end

  test "R266: mover troca a ordem; Demais não se move" do
    a = make_tier(@alfa, "A", person_type: "person")
    make_tier(@alfa, "B", min_overdue_days: 1)
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 20 } ], customers: [ customer_of(@alfa, FakeData.cpf(51)) ])
    recalc(@alfa)
    assert_equal "A", tier_of(contract)
    confirm(proposal.with_moved(a.id, "down"))
    assert_equal "B", tier_of(contract)
    assert_equal proposal.entries, proposal.with_moved(Tier.catch_all_of(@alfa).id, "up").entries
  end

  test "R272, R274: mudar um segmento usado passa pela proposta e registra o texto antes e depois" do
    tier = make_tier(@alfa, "Longo", min_overdue_days: 100)
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 50 } ])
    recalc(@alfa)
    segment = tier.segment
    segment.expression = { "all" => [ { "path" => "overdue_days", "op" => "gte", "value" => 30 } ] }
    confirm(proposal.with_segment(segment))
    assert_equal "Longo", tier_of(contract)
    log = Change.find_by!(subject_type: "segment", subject_id: segment.id, field: "expression")
    assert_equal [ "contratos\n  atraso >= 100", "contratos\n  atraso >= 30" ], [ log.before, log.after ]
  end

  test "R273: desativar um segmento usado tira o item da avaliação" do
    tier = make_tier(@alfa, "Todos", min_overdue_days: 0)
    contract = make_contract(@alfa, "P1", bills: [ { overdue: 5 } ])
    recalc(@alfa)
    segment = tier.segment
    segment.active = false
    confirm(proposal.with_segment(segment))
    assert_equal [ "Demais", false, false ], [ tier_of(contract), tier.reload.active, segment.reload.active ]
  end

  test "MT-19: o recálculo de um credor não mexe no outro, e a falha fica no registro dele" do
    make_tier(@beta, "Longo", min_overdue_days: 100)
    alfa = make_contract(@alfa, "A1", bills: [ { overdue: 200 } ])
    beta = make_contract(@beta, "B1", bills: [ { overdue: 200 } ])
    Tiers::Recalculation.new(@beta).call
    assert_equal [ nil, "Longo" ], [ tier_of(alfa), tier_of(beta) ]
    original = Segments::Compiler.method(:new)
    Segments::Compiler.define_singleton_method(:new) { |*| raise "falha simulada" }
    begin
      Tiers::Recalculation.new(@alfa).call
    ensure
      Segments::Compiler.define_singleton_method(:new, original)
    end
    run = TaskRun.where(tenant: @alfa, name: Tiers::Recalculation::NAME).last
    assert_equal "failed", run.status
  end

  test "R161: só tipo = PJ fora de um grupo qualquer dispensa o aviso do CDC; dentro do grupo, o item ainda aceita pessoa física" do
    pj = { "path" => "person_type", "op" => "eq", "value" => "company" }
    only_companies = make_tier(@alfa, "Só PJ", [ pj ], fine_pct: 10)
    grouped = make_tier(@alfa, "PJ ou atraso", [ { "any" => [ pj, { "path" => "overdue_days", "op" => "gt", "value" => 90 } ] } ], fine_pct: 10)
    assert_not only_companies.fine_above_cdc_limit?
    assert grouped.fine_above_cdc_limit?
  end
end
