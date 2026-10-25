require "test_helper"

# Registro da promessa junto do acionamento (10, R183 a R193, R189 a R191, R185, R188).
class Promises::RecorderTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(TODAY)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
  end

  teardown { travel_back }

  test "R183, R186, R191: a promessa da Maria nasce aberta, com o valor de cada título na data prometida e o número PRM-" do
    promise = register_promise(@customer, [ @nf1, @nf2 ])

    assert_predicate promise, :state_open?
    assert_equal "PRM-000001", promise.number
    assert_equal [ 106_047, 51_946 ], promise.promise_bills.includes(:bill).order("bills.due_date").references(:bills).map(&:total_cents)
    assert_equal 157_993, promise.total_cents
    first = promise.promise_bills.find_by(bill: @nf1)
    assert_equal({ "principal" => 100_000, "correction" => 534, "fine" => 2_011, "interest" => 3_502 }, first.components)
    assert_equal [ @nf1.id, @nf2.id ].sort, promise.promise_bills.where(held: true).pluck(:bill_id).sort
    assert_equal @customer, promise.customer
    assert_equal @nf1.contract, promise.contract
    assert_equal PROMISED, promise.promised_on
  end

  test "R187: a promessa guarda as políticas, a alçada e o segmento do momento; mudar a política depois não a muda" do
    promise = register_promise(@customer, [ @nf1 ])
    @alfa.setting.update!(promise_tolerance_days: 10, promise_counting: "also_direct")

    assert_equal 3, promise.reload.policies["tolerance_days"]
    assert_equal "promise_only", promise.policies["counting"]
    assert_equal 30, promise.policies["limit_days"]
    assert_equal Segment.catch_all_of(@alfa), promise.segment
  end

  test "R184: resultado que não admite promessa recusa o envio direto e nada é gravado" do
    message = refuse_message { register_promise(@customer, [ @nf1 ], result: :refused) }

    assert_equal I18n.t("promises.refused.result_not_allowed"), message
    assert_equal 0, ContactAttempt.count
    assert_equal 0, PaymentPromise.count
  end

  test "R184: o acionamento sem os campos da promessa continua valendo, mesmo com resultado que a admite" do
    attempt = record_attempt(@customer, users(:joana), result: result_of(@alfa, :promised))

    assert_nil attempt.promise
  end

  test "R185: o título de promessa aberta não entra em outra; o outro título entra" do
    register_promise(@customer, [ @nf1 ])

    assert_includes refuse_message { register_promise(@customer, [ @nf1 ]) }, "em promessa de Maria Souza"
    assert_predicate register_promise(@customer, [ @nf2 ]), :state_open?
  end

  test "R183b: a promessa é de um contrato só" do
    other = make_bill(@alfa, number: "NF-3", amount_cents: 20_000, contract_code: "CT-2", due: DUE)

    assert_equal I18n.t("promises.refused.one_contract"), refuse_message { register_promise(@customer, [ @nf1, other ]) }
    assert_predicate register_promise(@customer, [ other ]), :state_open?
  end

  test "R183a e R185a: Pedro e Ana, do mesmo contrato, têm promessas simultâneas sobre títulos diferentes" do
    pedro = Customer.create!(tenant: @alfa, document: Document.normalize(PaymentsHelper::JOAO), name: "Pedro")
    ContractCustomer.create!(contract: @nf1.contract, customer: pedro)
    promise = register_promise(pedro, [ @nf1 ])

    assert_equal pedro, promise.customer
    entries = Promises::Availability.new(@nf1.contract).entries.index_by { |entry| entry.bill.number }
    assert_equal "em promessa de Pedro", entries["NF-1"].blocked
    assert_nil entries["NF-2"].blocked
    assert_predicate register_promise(@customer, [ @nf2 ]), :state_open?
    assert_equal 2, @nf1.contract.bills.joins("join payment_promise_bills pb on pb.bill_id = bills.id").count
  end

  test "R183a: o cliente precisa figurar no contrato" do
    stranger = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "João", contract_code: "CT-9")

    assert_equal I18n.t("promises.refused.customer_not_in_contract"), refuse_message { register_promise(stranger, [ @nf1 ]) }
  end

  test "R190 e R191: o prazo acima da alçada do operador nasce pendente, sem número; o gestor dá o prazo do segmento" do
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    PromiseLimit.where(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_manager)).update_all(max_days: 60)
    pending = register_promise(@customer, [ @nf1 ], user: users(:carlos), on: TODAY + 45)
    own = register_promise(@customer, [ @nf2 ], user: users(:joana), on: TODAY + 45)

    assert_predicate pending, :state_pending?
    assert_nil pending.number
    assert_predicate own, :state_open?
    assert_equal "PRM-000001", own.number
  end

  test "R189 e R191: depois do prazo máximo do segmento a promessa é recusada com o limite" do
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)

    message = refuse_message { register_promise(@customer, [ @nf1 ], on: TODAY + 90) }

    assert_equal "A data prometida vai até 20/12/2026.", message
  end

  test "a data prometida não é anterior ao contato, e os campos obrigatórios são cobrados" do
    assert_equal I18n.t("promises.refused.date_before_contact"), refuse_message { register_promise(@customer, [ @nf1 ], on: TODAY - 1) }
    assert_equal I18n.t("promises.refused.bills_required"), refuse_message { register_promise(@customer, [], on: PROMISED, promise_contract_id: @nf1.contract_id) }
    assert_equal I18n.t("promises.refused.method"), refuse_message { register_promise(@customer, [ @nf1 ], method: "cheque") }
    assert_equal I18n.t("promises.refused.date_invalid"), refuse_message { record_attempt(@customer, users(:joana), result: result_of(@alfa, :promised), promise_contract_id: @nf1.contract_id, promise_bill_ids: [ @nf1.id.to_s ], promise_payment_method: "pix") }
  end

  test "R183 e R186: o contato retroativo conta o prazo máximo da data do contato" do
    promise = register_promise(@customer, [ @nf1 ], on: TODAY + 20, contacted_at: (Time.current - 5.days).strftime("%Y-%m-%dT%H:%M"))

    assert_equal TODAY - 5, promise.contacted_on
    assert_equal 25, promise.days_asked
    assert_predicate promise, :state_open?
  end

  test "R188: a carência do credor segura o título de promessa quebrada, cancelada ou recusada, de qualquer cliente" do
    @alfa.setting.update!(promise_grace_days: 7)
    promise = register_promise(@customer, [ @nf1 ])
    Promises::Canceller.new(users(:joana)).cancel(promise, "Pediu para negociar")

    assert_includes refuse_message { register_promise(@customer, [ @nf1 ]) }, "em carência até 28/10/2026"
    travel_day(TODAY + 7)
    assert_predicate register_promise(@customer, [ @nf1 ], on: TODAY + 9), :state_open?
  end

  test "sem carência (padrão) o título volta logo" do
    promise = register_promise(@customer, [ @nf1 ])
    Promises::Canceller.new(users(:joana)).cancel(promise, "Pediu para negociar")

    assert_predicate register_promise(@customer, [ @nf1 ]), :state_open?
  end

  test "V10: título de outro credor não entra na promessa" do
    beta = tenants(:beta)
    other = make_bill(beta, number: "NF-B", amount_cents: 30_000, contract_code: "CT-B", due: DUE)

    assert_equal I18n.t("promises.refused.bill_unknown"), refuse_message { register_promise(@customer, [ other ], promise_contract_id: @nf1.contract_id) }
  end

  test "R190 (revisão 5): a alçada, o prazo e o segmento são os do credor da promessa" do
    beta = tenants(:beta)
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    Segment.catch_all_of(beta).update!(promise_max_days: 90)
    PromiseLimit.where(segment: Segment.catch_all_of(@alfa), profile: profiles(:alfa_operator)).update_all(max_days: 30)
    PromiseLimit.where(segment: Segment.catch_all_of(beta), profile: profiles(:beta_operator)).update_all(max_days: 45)
    user = users(:ana) # Ana é operadora na Alfa e gestora na Beta; aqui a alçada do perfil dela em cada credor
    customer_beta, bill_beta, = promise_scenario(beta, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João")
    PromiseLimit.where(segment: Segment.catch_all_of(beta), profile: profiles(:beta_manager)).update_all(max_days: 45)

    alfa_promise = register_promise(@customer, [ @nf1 ], user: user, on: TODAY + 40)
    beta_promise = register_promise(customer_beta, [ bill_beta ], user: user, on: TODAY + 40)

    assert_predicate alfa_promise, :state_pending?
    assert_predicate beta_promise, :state_open?
  end
end
