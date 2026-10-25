require "test_helper"

# Termo, aceite registrado e a conferência da proposta ao aceitar (11, R219, R219a, R220, R220a).
class Agreements::AcceptanceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    @agreement = create_proposal(@customer, [ @nf1, @nf2 ])
  end

  teardown { travel_back }

  def at(hour, minute = 0, day: AGREEMENT_DAY) = day.in_time_zone.change(hour: hour, minute: minute)

  def accept(agreement = @agreement, by: @customer, presented: at(14, 50), accepted: at(15, 10), now: at(15, 30), actor: users(:carlos), **overrides)
    input = Agreements::Acceptance::Input.new("whatsapp", presented, "phone", accepted, "88213", by.id)
    input = input.with(**overrides) if overrides.any?
    Agreements::Acceptance.new(actor).call(agreement, input, now: now)
  end

  test "R220: o aceite por telefone às 15h10, com o termo enviado por WhatsApp às 14h50, deixa o acordo aguardando efetivação e guarda o termo" do
    accept

    @agreement.reload
    assert_predicate @agreement, :state_awaiting_effectuation?
    assert_equal [ "whatsapp", "phone", "88213" ], [ @agreement.presented_channel, @agreement.accepted_channel, @agreement.proof ]
    assert_equal [ at(14, 50), at(15, 10) ], [ @agreement.presented_at, @agreement.accepted_at ]
    assert_equal [ @customer, "financial_responsible", users(:carlos) ], [ @agreement.accepted_by_customer, @agreement.accepted_role, @agreement.registered_by ]
    assert_equal "ACD-000001", @agreement.term_snapshot["number"]
    assert_equal "19.5618", @agreement.term_snapshot["effective_annual_pct"]
    assert_equal 159_019, @agreement.term_snapshot["total_cents"]
    assert_equal({ "name" => "Maria Souza", "role" => "financial_responsible" }, @agreement.term_snapshot["accepted_by"])
    assert_equal %w[built accepted], @agreement.events.order(:id).map(&:kind)
    assert_equal [ @nf1.id, @nf2.id ].sort, AgreementBill.where(agreement: @agreement, held: true).pluck(:bill_id).sort, "os títulos seguem presos"
    assert_predicate @nf1.reload, :active?, "os originais seguem em cobrança até a efetivação (R221)"
  end

  test "R219: o termo traz os dados do credor, a taxa efetiva, a soma total e as políticas congeladas; o do aceite não muda quando o cadastro muda" do
    term = Agreements::Term.build(@agreement)

    assert_equal "Escola Alfa Ltda", term.dig("creditor", "legal_name")
    assert_equal "11.222.333/0001-81", term.dig("creditor", "cnpj")
    assert_equal [ "Maria Souza" ], term["addressees"].map { |item| item["name"] }
    assert_equal [ 157_993, 3_627, 154_366, 159_019, 4_653 ], term.values_at("base_cents", "discount_cents", "value_cents", "total_cents", "interest_cents")
    assert_equal [ "NF-1", "NF-2" ], term["bills"].map { |item| item["number"] }
    assert_equal %w[break_form late_charges tolerance_agreement], term["policies"].map { |line| line["key"] }.select { |key| %w[break_form late_charges tolerance_agreement].include?(key) }.sort
    assert_equal({ "fine_pct" => 2.0, "interest_pct" => 1.0 }, term["late"].slice("fine_pct", "interest_pct"))
    assert_equal 30, term.dig("variables", "break_days")

    accept
    @alfa.update!(legal_name: "Outra Razão Ltda")
    assert_equal "Escola Alfa Ltda", @agreement.reload.term_snapshot.dig("creditor", "legal_name"), "dados do credor apagados ou mudados depois do aceite: o termo guardado não muda"
  end

  test "R219: sem CNPJ e razão social do credor o rascunho não é gerado e o aceite é recusado dizendo o que falta" do
    @alfa.update_columns(cnpj: nil, legal_name: nil)

    assert_equal [ "CNPJ", "razão social" ], Agreements::Term.build(@agreement)["missing"]
    assert_equal I18n.t("agreements.accept_refused.no_term", missing: "CNPJ e razão social"), refuse_agreement { accept }
    assert_predicate @agreement.reload, :state_approved?
  end

  test "R219a: sem responsável financeiro declarado os titulares recebem o termo; com ele declarado, só ele" do
    pedro = Customer.create!(tenant: @alfa, document: Document.normalize(PaymentsHelper::JOAO), name: "Pedro Souza")
    ContractCustomer.create!(contract: @nf1.contract, customer: pedro, roles: [ "holder" ])
    ContractCustomer.find_by!(contract: @nf1.contract, customer: @customer).update!(roles: [ "holder" ])

    assert_equal [ "Maria Souza", "Pedro Souza" ], Agreements::Term.build(@agreement)["addressees"].map { |item| item["name"] }.sort

    ContractCustomer.find_by!(contract: @nf1.contract, customer: @customer).update!(roles: %w[holder financial_responsible])
    assert_equal [ "Maria Souza" ], Agreements::Term.build(@agreement)["addressees"].map { |item| item["name"] }
  end

  test "R220a: o titular que não é o responsável financeiro aceita no padrão; com 'só o responsável financeiro' é recusado" do
    pedro = Customer.create!(tenant: @alfa, document: Document.normalize(PaymentsHelper::JOAO), name: "Pedro Souza")
    ContractCustomer.create!(contract: @nf1.contract, customer: pedro, roles: [ "holder" ])
    ContractCustomer.find_by!(contract: @nf1.contract, customer: @customer).update!(roles: %w[holder financial_responsible])
    accept(by: pedro)

    assert_equal [ pedro, "holder" ], [ @agreement.reload.accepted_by_customer, @agreement.accepted_role ]

    @alfa.setting.update!(agreement_policies: { "who_accepts" => "financial_only" })
    @agreement.update!(state: "canceled")
    AgreementBill.where(agreement: @agreement).update_all(held: false)
    second = create_proposal(@customer, [ @nf2 ], installments: 2, down: 20_000)
    assert_equal I18n.t("agreements.accept_refused.acceptor_not_allowed"), refuse_agreement { accept(second, by: pedro) }
    accept(second)
    assert_equal "financial_responsible", second.reload.accepted_role
  end

  test "R220a: quem não é cliente de nenhum dos contratos dos títulos não aceita" do
    stranger = Customer.create!(tenant: @alfa, document: Document.normalize("111.444.777-35"), name: "Estranho")

    assert_equal I18n.t("agreements.accept_refused.acceptor_unknown"), refuse_agreement { accept(by: stranger) }
  end

  test "R220: proposta pendente, recusada ou expirada não pode ser aceita" do
    @agreement.update!(state: "pending")
    assert_equal I18n.t("agreements.accept_refused.not_approved"), refuse_agreement { accept }
    @agreement.update!(state: "expired")
    assert_equal I18n.t("agreements.accept_refused.not_approved"), refuse_agreement { accept }
  end

  test "R220: dois registros do aceite da mesma proposta: vale o primeiro" do
    accept

    assert_equal I18n.t("agreements.accept_refused.not_approved"), refuse_agreement { accept }
  end

  test "R217, R220: aceita-se até o fim do último dia da validade (04/11); no dia seguinte, não" do
    last = Date.new(2026, 11, 4)
    accept(presented: at(14, 0, day: last), accepted: at(23, 58, day: last), now: at(23, 59, day: last))
    assert_predicate @agreement.reload, :state_awaiting_effectuation?

    other = Agreement.find(@agreement.id)
    other.update!(state: "approved")
    next_day = Date.new(2026, 11, 5)
    assert_equal I18n.t("agreements.accept_refused.validity_passed"), refuse_agreement { accept(other, presented: at(9, 0, day: next_day), accepted: at(9, 5, day: next_day), now: at(10, 0, day: next_day)) }
  end

  test "R220: a apresentação e o aceite são posteriores à aprovação, a apresentação não é posterior ao aceite e o aceite não é futuro" do
    assert_equal I18n.t("agreements.accept_refused.presented_after_accepted"), refuse_agreement { accept(presented: at(16), accepted: at(15, 10)) }
    assert_equal I18n.t("agreements.accept_refused.accepted_future"), refuse_agreement { accept(accepted: at(16), now: at(15, 30)) }
    assert_equal I18n.t("agreements.accept_refused.before_approval"), refuse_agreement { accept(presented: at(8), accepted: at(9)) }
    assert_equal I18n.t("agreements.accept_refused.channel"), refuse_agreement { accept(presented_channel: "pombo") }
    assert_equal I18n.t("agreements.accept_refused.presented_time"), refuse_agreement { accept(presented: nil) }
    assert_equal I18n.t("agreements.accept_refused.proof_too_long", max: 200), refuse_agreement { accept(proof: "x" * 201) }
    assert_predicate @agreement.reload, :state_approved?
  end

  test "R220: a conferência recusa o aceite se o título saiu de cobrança, mudou de valor, recebeu pagamento ou teve pagamento estornado" do
    @nf2.update!(status: "withdrawn")
    assert_equal I18n.t("agreements.accept_refused.bill_left", number: "NF-2"), refuse_agreement { accept }
    @nf2.update!(status: "active")

    @nf1.update!(amount_cents: 90_000)
    assert_equal I18n.t("agreements.accept_refused.bill_value_changed", number: "NF-1"), refuse_agreement { accept }
    @nf1.update!(amount_cents: 100_000)

    @nf1.update!(paid_cents: 1_000)
    assert_equal I18n.t("agreements.accept_refused.bill_paid", number: "NF-1"), refuse_agreement { accept }
    @nf1.update!(paid_cents: 0)
    assert_predicate @agreement.reload, :state_approved?
  end

  test "R220: pagamento chegado depois da montagem e pagamento estornado depois dela recusam o aceite" do
    channel = make_channel(@alfa)
    travel_to at(13)
    payment = Payment.create!(tenant: @alfa, channel: channel, identifier: "P-1", document: "52998224725", bill_number: "NF-2", bill: @nf2, paid_on: AGREEMENT_DAY, amount_cents: 100, payment_method: "pix", status: "applied", applied_cents: 100)
    assert_equal I18n.t("agreements.accept_refused.bill_paid", number: "NF-2"), refuse_agreement { accept }
    payment.update_columns(created_at: at(11))

    PaymentReversal.create!(tenant: @alfa, channel: channel, payment: payment, identifier: "E-1", reversed_on: AGREEMENT_DAY, amount_cents: 100, from_credit_cents: 0, from_bill_cents: 100)
    assert_equal I18n.t("agreements.accept_refused.bill_reversed", number: "NF-2"), refuse_agreement { accept }
  end

  test "R220: a entrada já vencida recusa o aceite" do
    travel_day(Date.new(2026, 11, 6))
    @agreement.update_columns(valid_until: Date.new(2026, 11, 10))

    assert_equal I18n.t("agreements.accept_refused.down_overdue"), refuse_agreement { accept(presented: at(9, 0, day: Date.new(2026, 11, 6)), accepted: at(9, 5, day: Date.new(2026, 11, 6)), now: at(10, 0, day: Date.new(2026, 11, 6))) }
  end

  test "R219a, A8: o responsável financeiro sem contato cadastrado não bloqueia: a proposta traz o aviso e o aceite vale" do
    assert_includes @agreement.terms["warnings"], I18n.t("agreements.warnings.no_contact")
    accept

    assert_predicate @agreement.reload, :state_awaiting_effectuation?
  end

  test "R219a: com contato cadastrado o aviso não aparece" do
    @customer.contacts.create!(tenant: @alfa, kind: "phone", key: "11988887777", value: "(11) 98888-7777", origin: "screen")
    Agreements::Canceller.new(users(:carlos)).cancel(@agreement, "Reabrir")
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_not_includes quote.warnings, I18n.t("agreements.warnings.no_contact")
  end
end
