require "test_helper"

# Cobrança de cartão do checkout (12, R278): só o payment_token e as parcelas; resultado, recusas, idempotência e falhas de rede. Fornecedor falso.
class PaymentsCardChargerTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @checkout = make_checkout(customer: @customer)
    @charger = Payments::CardCharger.new
  end

  def charge(token = "tok-aprovado-1", installments: 1, checkout: @checkout) = @charger.charge(checkout, payment_token: token, installments: installments)

  def charges_in_provider = Payments::Providers::Fake.store[:instruments].values.count { |i| i[:kind] == "card" }

  test "aprova: grava a tentativa como instrumento de cartão ativo, o link passa a cartão aprovado e o aviso é transmitido (R278)" do
    outcome = nil
    assert_broadcasts(PaymentCheckoutChannel.broadcasting_for(@checkout), 1) { outcome = charge(installments: 3) }
    assert_equal :approved, outcome.kind
    attempt = @checkout.reload.card_instruments.sole
    assert_equal [ "card", "active", 99_900 ], [ attempt.kind, attempt.state, attempt.amount_cents ]
    assert attempt.external_id.start_with?("FAKE-CARD")
    assert_equal 3, attempt.response_summary["installments"]
    assert_equal @checkout, attempt.checkout
    assert @checkout.state_card_approved?
  end

  test "o fornecedor recebe só o token e as parcelas: nada de dado de cartão no instrumento nem no resumo" do
    charge("tok-sigiloso-xyz", installments: 2)
    attempt = @checkout.reload.card_instruments.sole
    assert_equal [], PaymentInstrument.column_names.grep(/card_number|cvv|holder|expir|token/i)
    assert_not_includes attempt.attributes.to_json, "tok-sigiloso-xyz"
    assert_not_includes attempt.response_summary.to_json, "tok-sigiloso-xyz"
  end

  test "a recusa sem nova tentativa (por segurança) guarda o código e o link continua aberto para outro cartão" do
    outcome = charge("recusado")
    assert_equal [ :declined, "security", false ], [ outcome.kind, outcome.code, outcome.retry ]
    assert @checkout.reload.state_open?
    attempt = @checkout.card_instruments.sole
    assert attempt.state_failed?
    assert_equal "security", attempt.response_summary["refusal_code"]
    assert_equal :approved, charge("tok-outro-cartao").kind
  end

  test "as recusas que podem repetir e a de dados inválidos trazem retry verdadeiro" do
    assert_equal [ :declined, "try_later", true ], charge("tente-depois").then { |o| [ o.kind, o.code, o.retry ] }
    assert_equal [ :declined, "invalid_data", true ], charge("dados-invalidos").then { |o| [ o.kind, o.code, o.retry ] }
  end

  test "clique duplo e retentativa: o mesmo token no mesmo link é a mesma tentativa, uma só cobrança no fornecedor" do
    assert_equal :approved, charge("tok-duplo-1").kind
    assert_equal :approved, charge("tok-duplo-1").kind
    assert_equal 1, charges_in_provider
    assert_equal 1, @checkout.reload.card_instruments.size
  end

  test "a recusa repetida com o mesmo token devolve a mesma recusa sem cobrar de novo" do
    first = charge("recusado")
    second = charge("recusado")
    assert_equal first, second
    assert_equal 1, charges_in_provider
  end

  test "link com cartão aprovado ou pago não aceita outra cobrança (não se paga duas vezes)" do
    charge("token-1-123456")
    assert_equal :approved, charge("token-2-123456").kind
    assert_equal 1, charges_in_provider
    @checkout.update!(state: "paid")
    assert_equal :paid, charge("token-3-123456").kind
    assert_equal 1, charges_in_provider
  end

  test "tentativa em curso com outro token barra a seguinte (processing)" do
    custom_id = Digest::SHA256.hexdigest("#{@checkout.id}:tok-em-curso").first(32)
    PaymentInstrument.create!(tenant: @alfa, account: Payments::Checkouts.card_account(@alfa, "production"), provider: "fake", checkout: @checkout, kind: "card", amount_cents: 99_900, due_on: Date.current,
                              custom_id: custom_id, state: "emitting")
    assert_equal :processing, charge("tok-em-curso").kind
    assert_equal :processing, charge("tok-outro").kind
    assert_equal 0, charges_in_provider
  end

  test "tentativa em curso há mais de 5 minutos vira não confirmada e o link não aceita mais cartão" do
    attempt = PaymentInstrument.create!(tenant: @alfa, account: Payments::Checkouts.card_account(@alfa, "production"), provider: "fake", checkout: @checkout, kind: "card", amount_cents: 99_900,
                                        due_on: Date.current, custom_id: "a" * 32, state: "emitting")
    attempt.update_columns(updated_at: 6.minutes.ago)
    assert_equal :unconfirmed, charge("tok-novo").kind
    assert @checkout.reload.state_card_unconfirmed?
    assert attempt.reload.state_failed?
  end

  test "falha em que a conexão nem saiu libera repetir o mesmo token; nada foi cobrado" do
    Payments::Providers::Fake.fail_on(:charge_card, Payments::Providers::NetworkError.new("fornecedor inacessível", retry_safe: true), times: 1)
    assert_equal :unavailable, charge("tok-rede-1").kind
    assert @checkout.reload.state_open?
    assert_equal 0, charges_in_provider
    assert_equal :approved, charge("tok-rede-1").kind
    assert_equal 1, @checkout.reload.card_instruments.size
    assert_equal 1, charges_in_provider
  end

  test "tempo esgotado ao ler a resposta pode ter cobrado: o link fica não confirmado e não aceita nova tentativa" do
    Payments::Providers::Fake.fail_on(:charge_card, Payments::Providers::NetworkError.new("o fornecedor não respondeu a tempo", retry_safe: false), times: 1)
    assert_equal :unconfirmed, charge("tok-lento").kind
    assert @checkout.reload.state_card_unconfirmed?
    assert_equal :unconfirmed, charge("tok-outro").kind
    assert_equal :unconfirmed, charge("tok-lento").kind
    assert_equal 0, charges_in_provider
  end

  test "erro do fornecedor (token inválido, por exemplo) é um erro genérico; outro token pode tentar" do
    Payments::Providers::Fake.fail_on(:charge_card, Payments::Providers::Error.new("token expirado"), times: 1)
    assert_equal :error, charge("tok-velho").kind
    assert_equal :error, charge("tok-velho").kind
    assert_equal :approved, charge("tok-novo-1").kind
  end

  test "parcelas: de 1 até o máximo da conta; fora disso, pedido inválido sem chamar o fornecedor" do
    assert_equal :invalid, charge("token-a-123456", installments: 7).kind
    assert_equal :invalid, charge("token-a-123456", installments: 0).kind
    assert_equal :invalid, charge("token-a-123456", installments: "abc").kind
    assert_equal 0, charges_in_provider
    assert_equal :approved, charge("token-a-123456", installments: 6).kind
  end

  test "token em formato estranho é recusado antes de qualquer chamada" do
    [ "", "curto", "com espaço no meio", "x" * 600, "<script>" ].each { |token| assert_equal :invalid, charge(token).kind }
    assert_equal 0, charges_in_provider
  end

  test "link vencido, cancelado ou sem cartão não cobra" do
    @checkout.update!(expires_at: 1.minute.ago)
    assert_equal :not_payable, charge("token-b-123456").kind
    @checkout.update!(expires_at: 1.day.from_now, state: "canceled")
    assert_equal :not_payable, charge("token-b-123456").kind
    only_boleto = Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ issued_instrument(@alfa, @customer, "boleto") ], card: false)
    assert_equal :not_payable, charge("token-b-123456", checkout: only_boleto).kind
    assert_equal 0, charges_in_provider
  end

  test "conta de cartão desativada depois do link: indisponível, sem cobrar" do
    Payments::Checkouts.card_account(@alfa, "production").update!(active: false)
    assert_equal :unavailable, charge("token-c-123456").kind
  end

  test "o custom_id da tentativa não guarda o token: é o SHA-256 do link e do token" do
    charge("tok-segredo-9")
    attempt = @checkout.reload.card_instruments.sole
    assert_equal Digest::SHA256.hexdigest("#{@checkout.id}:tok-segredo-9").first(32), attempt.custom_id
    assert_no_match(/tok-segredo/, attempt.custom_id)
  end
end
