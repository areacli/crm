require "test_helper"

# Aprovação, recusa, cancelamento, alçada que nasce com o segmento e o perfil, anonimização do motivo e exportação (10, R132, R190 a R193, R200).
class Promises::LifecycleTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(ChargesTestHelper::TODAY)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
    @segment = Segment.catch_all_of(@alfa)
    @segment.update!(promise_max_days: 60)
    PromiseLimit.where(segment: @segment, profile: profiles(:alfa_manager)).update_all(max_days: 60)
  end

  teardown { travel_back }

  def pending = register_promise(@customer, [ @nf1 ], user: users(:carlos), on: ChargesTestHelper::TODAY + 45)

  test "R192: aprovada, a pendente fica aberta com o número; as aprovações seguem a ordem" do
    promise = pending
    Promises::Reviewer.new(users(:joana)).approve(promise)
    other = register_promise(@customer, [ @nf2 ], user: users(:joana))

    assert_predicate promise.reload, :state_open?
    assert_equal "PRM-000001", promise.number
    assert_equal "PRM-000002", other.number
    assert Change.exists?(subject_type: "payment_promise", subject_id: promise.id, event: "approved")
  end

  test "R192: a política só deixa aprovar quem tem alçada e nunca quem registrou" do
    promise = pending
    assert_not PaymentPromisePolicy.new(users(:carlos), promise).approve?
    assert_not PaymentPromisePolicy.new(users(:ana), promise).approve?
    assert PaymentPromisePolicy.new(users(:joana), promise).approve?
    assert_not PaymentPromisePolicy.new(users(:joana), register_promise(@customer, [ @nf2 ], user: users(:joana))).approve?
  end

  test "R193: aprovar depois do prazo é recusado; a recusa libera os títulos" do
    promise = pending
    Promises::Reviewer.new(users(:joana)).refuse(promise, "Prazo longo")
    assert_predicate promise.reload, :state_refused?
    assert_equal "Prazo longo", promise.reason
    assert_predicate register_promise(@customer, [ @nf1 ]), :state_open?

    late = register_promise(@customer, [ @nf2 ], user: users(:carlos), on: ChargesTestHelper::TODAY + 45)
    travel_day(ChargesTestHelper::TODAY + 49)
    assert_equal I18n.t("promises.refused.deadline_passed"), refuse_message { Promises::Reviewer.new(users(:joana)).approve(late) }
  end

  test "R200: o cancelamento exige motivo de até 300 caracteres e libera os títulos; o pago continua pago" do
    promise = register_promise(@customer, [ @nf1, @nf2 ])
    canceller = Promises::Canceller.new(users(:joana))
    assert_equal I18n.t("promises.refused.cancel_reason_required"), refuse_message { canceller.cancel(promise, " ") }
    assert_equal I18n.t("promises.refused.reason_too_long", max: 300), refuse_message { canceller.cancel(promise, "x" * 301) }
    canceller.cancel(promise, "Pediu para negociar")

    assert_predicate promise.reload, :state_canceled?
    assert_empty promise.promise_bills.where(held: true)
    assert_equal I18n.t("promises.refused.not_cancelable"), refuse_message { canceller.cancel(promise, "de novo") }
  end

  test "R190: a alçada nasce com o segmento e com o perfil, pelo padrão: gestor com o prazo do segmento, operador até 30 dias" do
    segment = Segment.create!(tenant: @alfa, name: "Varejo PF recente", promise_max_days: 90)
    assert_equal 90, PromiseLimit.find_by(segment: segment, profile: profiles(:alfa_manager)).max_days
    assert_equal 30, PromiseLimit.find_by(segment: segment, profile: profiles(:alfa_operator)).max_days

    profile = Profile.create!(tenant: @alfa, name: "Supervisor", permissions: %w[view_portfolio record_contact_attempts change_financial_policies])
    assert_equal 90, PromiseLimit.find_by(segment: segment, profile: profile).max_days
    assert_equal 60, PromiseLimit.find_by(segment: @segment, profile: profile).max_days
  end

  test "R190: baixar o prazo do segmento baixa a alçada que passava dele; subir não sobe nenhuma" do
    settings = Promises::Settings.new(users(:joana))
    settings.update_limits(@alfa, { @segment.id => { max_days: 20, limits: {} } })
    assert_equal [ 20, 20 ], PromiseLimit.where(segment: @segment, profile: [ profiles(:alfa_manager), profiles(:alfa_operator) ]).order(:id).pluck(:max_days)

    settings.update_limits(@alfa, { @segment.id => { max_days: 90, limits: {} } })
    assert_equal [ 20, 20 ], PromiseLimit.where(segment: @segment, profile: [ profiles(:alfa_manager), profiles(:alfa_operator) ]).order(:id).pluck(:max_days)
    assert_equal I18n.t("promises.settings.invalid_limit", segment: "Demais"), refuse_message { settings.update_limits(@alfa, { @segment.id => { max_days: 30, limits: { profiles(:alfa_operator).id => 40 } } }) }
  end

  test "R187: mudar a alçada e as políticas não mexe nas promessas existentes" do
    promise = register_promise(@customer, [ @nf1 ])
    Promises::Settings.new(users(:joana)).update_policies(@alfa, { promise_tolerance_days: "9", promise_grace_days: "5" })
    Promises::Settings.new(users(:joana)).update_limits(@alfa, { @segment.id => { max_days: 10, limits: {} } })

    assert_equal 3, promise.reload.policies["tolerance_days"]
    assert_equal 9, promise.days_asked
    assert_predicate promise, :state_open?
  end

  test "R132: o motivo da promessa sai na anonimização do cliente e a exportação traz as promessas" do
    promise = register_promise(@customer, [ @nf1 ])
    Promises::Canceller.new(users(:joana)).cancel(promise, "Falei com a avó dela")
    export = Titular::Exporter.new(@customer).to_h
    assert_equal "Falei com a avó dela", export[:promessas].first[:motivo]

    Titular::Anonymizer.in_batch(@alfa.id, [ @customer.id ])
    assert_equal "removido na anonimização", promise.reload.reason
    assert_equal "removido na anonimização", Change.where(subject_type: "payment_promise", subject_id: promise.id, event: "state_changed").first.note
  end

  test "a numeração é por credor, sem pular nem repetir" do
    beta = tenants(:beta)
    customer_b, bill_b, = promise_scenario(beta, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João")
    assert_equal "PRM-000001", register_promise(@customer, [ @nf1 ]).number
    assert_equal "PRM-000001", register_promise(customer_b, [ bill_b ], user: users(:ana)).number
    assert_equal "PRM-000002", register_promise(@customer, [ @nf2 ]).number
  end

  test "o banco garante um título em uma promessa só" do
    promise = register_promise(@customer, [ @nf1 ])
    other = PaymentPromise.new(promise.attributes.except("id", "number", "contact_attempt_id")).tap { |item| item.contact_attempt = record_attempt(@customer, users(:joana), text: "outro") }
    other.save!
    assert_raises(ActiveRecord::RecordNotUnique) { other.promise_bills.create!(bill: @nf1, total_cents: 1, principal_cents: 1) }
  end
end
