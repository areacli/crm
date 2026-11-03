require "test_helper"

# Enquadramento da fila (15, R349 a R352, R355): o primeiro item que casa, sem regra de entrada; "sem fila"; a posição pela ordem da fila;
# o retorno lido do último acionamento.
class QueuesRecalculationTest < ActiveSupport::TestCase
  include SegmentsTestHelper

  setup do
    @alfa = tenants(:alfa)
    @result = contact_results(:alfa_promised)
  end

  def queue(name, segment, subject: "contracts", delivers: true, position: 1, **attributes)
    WorkQueue.create!(tenant: @alfa, subject: subject, name: name, segment: segment, delivers: delivers, position: position, **attributes)
  end

  def expr(subject, *conditions) = Segments::Expression.new("grammar" => 1, "subject" => subject, "all" => conditions)
  def run_query(query) = ActiveRecord::Base.connection.select_all(query.sql, "Segments", query.binds).to_a

  def placement(record, subject = "contracts") = QueuePlacement.find_by(subject: subject, subject_id: record.id)

  def recalc(**options) = Queues::Recalculation.new(@alfa).apply(**options)

  def attempt(customer, contract: nil, at: 1.hour.ago, return_at: nil, user: users(:joana))
    ContactAttempt.create!(tenant: @alfa, customer: customer, contract: contract, user: user, result: @result, result_kind: @result.kind, channel: "phone",
                           contacted_at: at, return_at: return_at)
  end

  test "R349: o primeiro item que casa; \"sem fila\"; a trilha padrão começa sem fila" do
    promise = make_segment(@alfa, "Promessa", [ { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "open" } } ])
    late = make_segment(@alfa, "Atraso 31 a 90", [ { "path" => "overdue_days", "op" => "between", "value" => [ 31, 90 ] } ])
    queue("Promessa ou acordo em dia", promise, delivers: false, position: 1)
    a = queue("Fila A", late, position: 2)
    c77 = make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    c80 = make_contract(@alfa, "C-80", bills: [ { overdue: 200 } ])
    recalc
    assert_equal a.id, placement(c77).work_queue_id
    assert_nil placement(c80).work_queue_id, "não casou com nenhum item: trilha padrão, sem fila"
    assert WorkQueue.find_by(tenant: @alfa, subject: "contracts", catch_all: true).delivers == false
  end

  test "R350: não há regra de entrada; uma fila de busca de contato pega cliente sem título nenhum" do
    seek = make_segment(@alfa, "Sem contato válido", [ { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" } ], subject: "customers")
    queue("Busca de contato", seek, subject: "customers")
    maria = customer_of(@alfa, FakeData.cpf(301), "Maria")
    recalc
    assert_equal "Busca de contato", placement(maria, "customers").work_queue.name
  end

  test "R355: a posição segue o critério, o desempate e o sujeito mais antigo" do
    all = make_segment(@alfa, "Em cobrança", [ { "path" => "in_collection", "op" => "is" } ])
    a = queue("Fila A", all, order_by: "overdue_balance", order_tiebreak: "overdue_days")
    small = make_contract(@alfa, "C-1", bills: [ { overdue: 10, cents: 10_000 } ])
    big = make_contract(@alfa, "C-2", bills: [ { overdue: 10, cents: 90_000 } ])
    tie_old = make_contract(@alfa, "C-3", bills: [ { overdue: 50, cents: 50_000 } ])
    tie_new = make_contract(@alfa, "C-4", bills: [ { overdue: 20, cents: 50_000 } ])
    recalc
    order = QueuePlacement.where(work_queue_id: a.id).order(:rank).pluck(:subject_id)
    assert_equal [ big.id, tie_old.id, tie_new.id, small.id ], order
  end

  test "R352 (revisão 1): o callback lê o retorno do último acionamento; o retorno feito tira o contrato da fila" do
    callback = make_segment(@alfa, "Callback", [ { "path" => "return_days", "op" => "lte", "value" => 0 } ])
    queue("Callback", callback)
    c12 = make_contract(@alfa, "C-12", bills: [ { overdue: 10 } ])
    customer = c12.customers.first
    attempt(customer, contract: c12, at: 2.hours.ago, return_at: 1.hour.from_now)
    recalc
    assert_equal "Callback", placement(c12).work_queue&.name
    attempt(customer, contract: c12, at: 10.minutes.ago)
    recalc(only: { "contracts" => [ c12.id ] })
    assert_nil placement(c12).work_queue_id
  end

  test "R351: o recálculo do sujeito só mexe nos sujeitos dados" do
    late = make_segment(@alfa, "Atraso", [ { "path" => "overdue_days", "op" => "gt", "value" => 0 } ])
    queue("Fila A", late)
    one = make_contract(@alfa, "C-1", bills: [ { overdue: 10 } ])
    recalc
    two = make_contract(@alfa, "C-2", bills: [ { overdue: 10 } ])
    recalc(only: { "contracts" => [ one.id ] })
    assert_nil placement(two), "quem não foi pedido só entra no recálculo completo"
    recalc
    assert_not_nil placement(two)
  end

  test "R351: avaliar só alguns sujeitos dá o mesmo resultado que avaliar todos, com coleções, pais e outros contratos" do
    expressions = [
      [ { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 2 } ],
      [ { "path" => "holder.other_contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 1 } ],
      [ { "path" => "return_days", "op" => "lte", "value" => 0 } ],
      [ { "path" => "in_collection", "op" => "is" }, { "path" => "contact_attempts", "quantifier" => "none", "within_days" => 30 } ]
    ]
    ana = customer_of(@alfa, FakeData.cpf(401), "Ana")
    one = make_contract(@alfa, "R-1", bills: [ { overdue: 40 }, { overdue: 10 } ], customers: [ ana ])
    two = make_contract(@alfa, "R-2", bills: [ { overdue: 5 } ], customers: [ ana ])
    three = make_contract(@alfa, "R-3", bills: [ { overdue: -5 } ])
    attempt(ana, contract: two, return_at: 1.hour.from_now)
    compiler = Segments::Compiler.new(@alfa)
    expressions.each do |conditions|
      entries = [ [ 1, expr("contracts", *conditions) ] ]
      all = run_query(compiler.classify_subjects("contracts", entries, default_id: 0)).to_h { [ _1["subject_id"], _1["item_id"] ] }
      some = run_query(Segments::Compiler.new(@alfa).classify_subjects("contracts", entries, default_id: 0, only_ids: [ one.id, three.id ])).to_h { [ _1["subject_id"], _1["item_id"] ] }
      assert_equal all.slice(one.id, three.id), some, conditions.inspect
    end
    customer_entries = [ [ 1, expr("customers", { "path" => "contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 2 }) ] ]
    some = run_query(Segments::Compiler.new(@alfa).classify_subjects("customers", customer_entries, default_id: 0, only_ids: [ ana.id ])).to_h { [ _1["subject_id"], _1["item_id"] ] }
    assert_equal({ ana.id => 1 }, some)
  end
end
