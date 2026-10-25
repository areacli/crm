require "test_helper"

# Gravação da proposta, alçada, aprovação, recusa, validade, cancelamento e substituição (11, R210 a R218).
class Agreements::ProposalTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
  end

  teardown { travel_back }

  test "R210, R211: a proposta da Maria é gravada aprovada, com número, validade, parcelas e os dois títulos presos" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ])

    assert_equal "ACD-000001", agreement.number
    assert_predicate agreement, :state_approved?
    assert_equal users(:carlos), agreement.user
    assert_equal [ AGREEMENT_DAY, Date.new(2026, 11, 4) ], [ agreement.built_on, agreement.valid_until ], "montada em 30/10 com validade de 5 dias vale até o fim de 04/11"
    assert_equal [ 157_993, 3_627, 154_366, 154_366, 34_366 ], [ agreement.base_cents, agreement.discount_cents, agreement.value_cents, agreement.net_cents, agreement.down_payment_cents ]
    assert_equal [ 4, "price", 159_019 ], [ agreement.installments_count, agreement.installment_method, agreement.total_cents ]
    assert_equal BigDecimal("19.5618"), agreement.effective_annual_pct
    assert_equal 5, agreement.schedule.size
    assert_equal [ 103_290, 51_076 ], agreement.agreement_bills.order(:id).map(&:value_cents)
    assert_equal({ "fine" => 1_006, "interest" => 1_751 }, agreement.agreement_bills.find_by(bill: @nf1).discount)
    assert_equal [ @nf1.id, @nf2.id ].sort, AgreementBill.where(agreement: agreement, held: true).pluck(:bill_id).sort
    assert_equal %w[built], agreement.events.map(&:kind)
    assert_equal({ "fine" => 5_000, "interest" => 5_000 }, agreement.discounts.slice("fine", "interest").transform_values(&:to_i))
  end

  test "R210: tudo o que é do acordo fica congelado: variáveis, parâmetros, limite de quem montou, políticas e praça" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ])
    @alfa.setting.update!(installment_rate_pct: 3, agreement_policies: { "break_form" => "single_title", "effectuation" => "acceptance" })
    Segment.catch_all_of(@alfa).update!(agreement_break_days: 10, agreement_max_installments: 2)
    terms = agreement.reload.terms

    assert_equal 30, terms.dig("segment", "break_days")
    assert_equal 12, terms.dig("segment", "max_installments")
    assert_equal "1.5", terms.dig("parameters", "installment_rate_pct")
    assert_equal "price", terms.dig("parameters", "installment_method")
    assert_equal "installments_follow", terms.dig("policies", "break_form")
    assert_equal "payment", terms.dig("policies", "effectuation")
    assert_equal({ "kind" => "cents", "value" => 100 }, terms.dig("policies", "tolerance_agreement"))
    assert_equal "Operador", terms.dig("limit", "profile")
    assert_equal 6, terms.dig("limit", "max_installments")
    assert_equal 50, terms.dig("limit", "caps", "installment", "fine")
    assert_nil terms.dig("square", "municipality_id")
    assert_includes terms["warnings"], I18n.t("agreements.warnings.city_unrecognized")
    assert_equal 0.02, terms.dig("parameters", "late_rule", "fine")
    assert_not terms["policies"].key?("credit_use"), "as políticas que não são do acordo valem como estão no dia"
  end

  test "R216: fora dos limites do Operador a proposta nasce pendente, não é aprovada por quem a montou e o gestor a aprova" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 10_000, "interest" => 5_000 })

    assert_predicate agreement, :state_pending?
    assert_nil agreement.decided_at
    assert_not AgreementPolicy.new(users(:carlos), agreement).approve?, "nunca quem a montou"
    assert_not AgreementPolicy.new(users(:ana), agreement).approve?, "os limites da Ana não a cobririam"
    assert AgreementPolicy.new(users(:joana), agreement).approve?

    Agreements::Reviewer.new(users(:joana)).approve(agreement)
    assert_predicate agreement.reload, :state_approved?
    assert_equal [ users(:joana), true ], [ agreement.decided_by, agreement.decided_at.present? ]
    assert_equal %w[built approved], agreement.events.order(:id).map(&:kind)
    assert_equal I18n.t("agreements.refused.not_pending"), refuse_agreement { Agreements::Reviewer.new(users(:joana)).approve(agreement) }
  end

  test "R216: quem aprova pode recusar, com motivo; vale a primeira gravação e os títulos ficam livres" do
    agreement = create_proposal(@customer, [ @nf1 ], discounts: { "fine" => 10_000 })
    reviewer = Agreements::Reviewer.new(users(:joana))

    assert_equal I18n.t("agreements.refused.reason_required"), refuse_agreement { reviewer.refuse(agreement, " ") }
    reviewer.refuse(agreement, "Desconto alto demais")

    assert_predicate agreement.reload, :state_refused?
    assert_equal "Desconto alto demais", agreement.reason
    assert_empty AgreementBill.where(agreement: agreement, held: true)
    assert_equal I18n.t("agreements.refused.not_pending"), refuse_agreement { reviewer.approve(agreement) }
  end

  test "R216: o perfil com limites maiores aprova a que o Operador não podia; a política do Gestor acompanha o segmento" do
    limit = AgreementLimit.for(profiles(:alfa_manager), Segment.catch_all_of(@alfa))
    assert_equal [ 12, 10 ], [ limit.max_installments, limit.min_down_payment_pct ]
    assert_equal 100, Agreements::Caps.get(limit.caps, "installment", "fine")
    operator = AgreementLimit.for(profiles(:alfa_operator), Segment.catch_all_of(@alfa))
    assert_equal [ 6, 10, 50, 25 ], [ operator.max_installments, operator.min_down_payment_pct, Agreements::Caps.get(operator.caps, "installment", "fine"), Agreements::Caps.get(operator.caps, "installment", "fees") ]
  end

  test "R217: a proposta vale até o fim do último dia da validade; depois, a aprovada expira e a pendente fica não aprovada" do
    approved = create_proposal(@customer, [ @nf1 ])
    pending = create_proposal(@customer, [ @nf2 ], discounts: { "fine" => 10_000 }, down: 5_900)

    Agreements::Daily.new(@alfa).apply(today: Date.new(2026, 11, 4))
    assert_predicate approved.reload, :state_approved?, "ainda vale em 04/11"

    travel_day(Date.new(2026, 11, 5))
    assert_equal 2, Agreements::Daily.new(@alfa).apply(today: Date.new(2026, 11, 5))
    assert_predicate approved.reload, :state_expired?
    assert_predicate pending.reload, :state_not_approved?
    assert_empty AgreementBill.where(held: true)
    assert_equal %w[built expired], approved.events.order(:id).map(&:kind)
    assert_equal %w[built not_approved], pending.events.order(:id).map(&:kind)
  end

  test "R217: aprovar depois da validade é recusado" do
    agreement = create_proposal(@customer, [ @nf1 ], discounts: { "fine" => 10_000 })
    travel_day(Date.new(2026, 11, 5))

    assert_equal I18n.t("agreements.refused.validity_passed"), refuse_agreement { Agreements::Reviewer.new(users(:joana)).approve(agreement) }
  end

  test "R217: a tarefa diária registra a execução e não mexe em proposta de outro credor" do
    other = tenants(:beta)
    run = Agreements::Daily.new(other).call(today: Date.new(2026, 12, 1))

    assert_predicate run, :succeeded?
    assert_equal [ 0, "agreements_daily" ], [ run.processed, run.name ]
    approved = create_proposal(@customer, [ @nf1 ])
    Agreements::Daily.new(other).apply(today: Date.new(2026, 12, 1))
    assert_predicate approved.reload, :state_approved?
  end

  test "R218: o título de proposta vigente não entra em outra; cancelar exige motivo e libera os títulos" do
    first = create_proposal(@customer, [ @nf1 ])

    assert_equal I18n.t("agreements.refused.bill_held", number: "NF-1", agreement: first.number), refuse_agreement { simulate_agreement(@customer, [ @nf1 ]) }
    canceller = Agreements::Canceller.new(users(:ana))
    assert_equal I18n.t("agreements.refused.cancel_reason_required"), refuse_agreement { canceller.cancel(first, "") }
    canceller.cancel(first, "Cliente desistiu")

    assert_predicate first.reload, :state_canceled?
    assert_equal "Cliente desistiu", first.reason
    assert_equal %w[built canceled], first.events.order(:id).map(&:kind)
    assert_empty AgreementBill.where(agreement: first, held: true)
    assert_equal I18n.t("agreements.refused.not_cancelable"), refuse_agreement { canceller.cancel(first, "de novo") }
    assert_predicate create_proposal(@customer, [ @nf1 ]), :state_approved?
  end

  test "R218, DA33: outra operadora monta outra proposta que substitui a primeira, com o registro 'substituída por ACD-000002'" do
    first = create_proposal(@customer, [ @nf1, @nf2 ])
    second = create_proposal(@customer, [ @nf1, @nf2 ], user: users(:ana), replace: true)

    assert_equal "ACD-000002", second.number
    assert_predicate first.reload, :state_canceled?
    assert_equal "substituída por ACD-000002", first.reason
    assert_equal %w[built replaced], first.events.order(:id).map(&:kind)
    assert_equal [ second.id ], AgreementBill.where(held: true).pluck(:agreement_id).uniq
  end

  test "R218: só a proposta é substituída; o acordo aceito prende os títulos" do
    first = create_proposal(@customer, [ @nf1 ])
    first.update!(state: "awaiting_effectuation")

    assert_equal I18n.t("agreements.refused.bill_held", number: "NF-1", agreement: first.number), refuse_agreement { create_proposal(@customer, [ @nf1 ], replace: true) }
  end

  test "R183 (10): o título em proposta de acordo não entra em promessa nova" do
    create_proposal(@customer, [ @nf1 ])

    assert_includes refuse_message { register_promise(@customer, [ @nf1 ], on: AGREEMENT_DAY + 3) }, "em proposta ou acordo ACD-000001"
    assert_predicate register_promise(@customer, [ @nf2 ], on: AGREEMENT_DAY + 3), :state_open?
  end

  test "R222 (11, etapa 3): a promessa aberta dos títulos continua aberta enquanto a proposta não é aceita" do
    promise = register_promise(@customer, [ @nf1 ], on: AGREEMENT_DAY + 3)
    create_proposal(@customer, [ @nf1 ])

    assert_predicate promise.reload, :state_open?
  end

  test "R210: o número do acordo é sequência por credor" do
    Segment.catch_all_of(tenants(:beta)).update!(**AgreementsTestHelper::EXAMPLE_VARIABLES)
    beta_customer, beta_nf = promise_scenario(tenants(:beta), document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João Souza").then { |customer, bill, _| [ customer, bill ] }
    rebuild_agreement_limits(tenants(:beta))
    a = create_proposal(@customer, [ @nf1 ])
    b = create_proposal(beta_customer, [ beta_nf ], user: users(:marta))

    assert_equal [ "ACD-000001", "ACD-000001" ], [ a.number, b.number ]
    assert_equal [ @alfa.id, tenants(:beta).id ], [ a.tenant_id, b.tenant_id ]
  end

  test "MT-2, V10: quem não tem vínculo ativo no credor do cliente não simula nem grava" do
    assert_equal I18n.t("agreements.refused.no_profile"), refuse_agreement { simulate_agreement(@customer, [ @nf1 ], user: users(:marta)) }
    assert_equal 0, Agreement.count
  end

  test "R211: a proposta não é gravada quando a simulação é recusada (R215)" do
    assert_equal I18n.t("agreements.refused.discount_none", component: "principal"), refuse_agreement { create_proposal(@customer, [ @nf1, @nf2 ], discounts: { "principal" => 1_000 }) }
    assert_equal [ 0, 0, 0 ], [ Agreement.count, AgreementBill.count, AgreementEvent.count ]
    assert_equal 0, @alfa.setting.reload.agreement_sequence, "a sequência não anda quando a proposta não é gravada"
  end

  test "R210a: o limite do perfil do usuário no credor do acordo vale, e a mesma pessoa tem limites diferentes em credores diferentes" do
    ana_alfa = Agreements::Limits.limit_of(users(:ana), Agreement.new(tenant: @alfa, segment: Segment.catch_all_of(@alfa)))
    assert_equal 6, ana_alfa.max_installments, "Operadora na Alfa"
    beta_segment = Segment.catch_all_of(tenants(:beta))
    beta_segment.update!(**AgreementsTestHelper::EXAMPLE_VARIABLES)
    rebuild_agreement_limits(tenants(:beta))
    ana_beta = Agreements::Limits.limit_of(users(:ana), Agreement.new(tenant: tenants(:beta), segment: beta_segment))
    assert_equal 12, ana_beta.max_installments, "Gestora na Beta"
  end
end
