require "test_helper"

# Links de checkout (12, parte C, R277, R280): criação só por serviço, token, validade, formas oferecidas, valor emitido, estado e renovação.
class PaymentsCheckoutsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
  end

  test "o token tem 256 bits (43 caracteres URL-safe), é único e é o parâmetro do link (R277)" do
    first = make_checkout
    second = make_checkout(customer: @customer)
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, first.token)
    assert_not_equal first.token, second.token
    assert_equal first.token, first.to_param
    assert_equal 32, Base64.urlsafe_decode64(first.token).bytesize
  end

  test "só cartão: oferece o cartão, em destaque, válido por 30 dias, com a cópia mínima do pagador" do
    checkout = make_checkout
    assert_equal [ "card" ], checkout.modalities
    assert_equal "card", checkout.highlight
    assert checkout.state_open?
    assert_in_delta (Time.current + 30.days).to_f, checkout.expires_at.to_f, 5
    assert_equal [ "Maria Souza", "52998224725", 99_900 ], [ checkout.payer_name, checkout.payer_document, checkout.amount_cents ]
    assert_equal 0, checkout.access_count
  end

  test "com boleto e Pix emitidos: as formas oferecidas são as deles mais o cartão, o destaque é o Pix, o link vale até o vencimento mais 30 dias e os instrumentos ficam ligados (R277)" do
    checkout = make_checkout(boleto: true, pix: true)
    assert_equal %w[boleto pix card].sort, checkout.modalities.sort
    assert_equal "pix", checkout.highlight
    assert_equal (Date.current + 10 + 30).end_of_day.to_i, checkout.expires_at.in_time_zone.to_i
    assert_equal 2, checkout.instruments.count
    assert_equal %w[boleto pix], checkout.instruments.order(:kind).pluck(:kind)
  end

  test "o destaque pode ser escolhido entre as formas oferecidas, e outra forma é recusada" do
    checkout = make_checkout(boleto: true, pix: true, highlight: "boleto")
    assert_equal "boleto", checkout.highlight
    assert_raises(Payments::Checkouts::Refused) { make_checkout(card: true, highlight: "pix", customer: @customer) }
  end

  test "sem conta de cartão ativa o cartão não é oferecido; sem nenhuma forma, o link não nasce" do
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, amount_cents: 1_000) }
    boleto = issued_instrument(@alfa, @customer, "boleto")
    checkout = Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ boleto ])
    assert_equal [ "boleto" ], checkout.modalities
    assert_equal boleto.amount_cents, checkout.amount_cents
  end

  test "pedir cartão sem conta ativa ou sem documento válido do pagador é recusado" do
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, amount_cents: 1_000, card: true) }
    make_card_account(@alfa)
    @customer.update_columns(document: "11111111111")
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, amount_cents: 1_000, card: true) }
    assert_nothing_raised { Payments::Checkouts.create(tenant: @alfa, customer: @customer, card: false, instruments: [ issued_instrument(@alfa, make_customer(@alfa, document: PaymentsHelper::JOAO, name: "João"), "pix") ]) }
  end

  test "o valor é o emitido (R280): instrumentos de valores diferentes ou valor informado diferente são recusados" do
    boleto = issued_instrument(@alfa, @customer, "boleto", amount_cents: 10_000)
    pix = issued_instrument(@alfa, @customer, "pix", amount_cents: 12_000)
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ boleto, pix ]) }
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ boleto ], amount_cents: 9_999) }
  end

  test "instrumento de outro credor, cancelado ou de cartão não entra no link" do
    beta = tenants(:beta)
    other = issued_instrument(beta, make_customer(beta, document: PaymentsHelper::JOAO, name: "João"), "boleto")
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ other ]) }
    canceled = issued_instrument(@alfa, @customer, "boleto")
    canceled.update_columns(state: "canceled")
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ canceled ]) }
  end

  test "renovar soma dias à validade que restar; link pago ou cancelado não se renova (R277)" do
    checkout = make_checkout
    before = checkout.expires_at
    Payments::Checkouts.renew(checkout, days: 10)
    assert_in_delta (before + 10.days).to_f, checkout.expires_at.to_f, 1
    checkout.update_columns(expires_at: 3.days.ago)
    Payments::Checkouts.renew(checkout, days: 30)
    assert_in_delta (Time.current + 30.days).to_f, checkout.reload.expires_at.to_f, 5
    checkout.update!(state: "paid")
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.renew(checkout) }
  end

  test "vencido ou cancelado, o link não está disponível" do
    checkout = make_checkout
    assert checkout.available?
    checkout.update!(expires_at: 1.minute.ago)
    assert_not checkout.available?
    checkout.update!(expires_at: 1.day.from_now, state: "canceled")
    assert_not checkout.available?
  end

  test "o estado acompanha os instrumentos: cartão aprovado, pago, e o pago não volta atrás (sync)" do
    checkout = make_checkout(boleto: true)
    boleto = checkout.instruments.first
    assert_no_changes(-> { checkout.reload.state }) { Payments::Checkouts.sync(checkout) }
    assert_broadcasts(PaymentCheckoutChannel.broadcasting_for(checkout), 1) { boleto.update!(state: "paid"); Payments::Checkouts.sync(checkout) }
    assert checkout.reload.state_paid?
    boleto.update!(state: "active")
    Payments::Checkouts.sync(checkout)
    assert checkout.reload.state_paid?
  end

  test "cancelar o link transmite o aviso e o pago não se cancela" do
    checkout = make_checkout
    assert_broadcasts(PaymentCheckoutChannel.broadcasting_for(checkout), 1) { Payments::Checkouts.cancel(checkout) }
    assert checkout.state_canceled?
    paid = make_checkout(customer: @customer)
    paid.update!(state: "paid")
    assert_raises(Payments::Checkouts::Refused) { Payments::Checkouts.cancel(paid) }
  end

  test "boleto vencido paga até days_to_write_off da conta (R280)" do
    checkout = make_checkout(boleto: true)
    boleto = checkout.instruments.first
    boleto.update_columns(due_on: Date.current - 10)
    assert_equal boleto.due_on + 30, checkout.boleto_payable_until(boleto)
    assert checkout.boleto_payable?(boleto)
    boleto.account.update!(config: boleto.account.config.merge("write_off_days" => 5))
    assert_not checkout.boleto_payable?(boleto.reload)
  end

  test "o link guarda e-mail e telefone válidos do cadastro para o cartão" do
    add_contact(@customer, "email", "maria@exemplo.com.br")
    add_contact(@customer, "phone", "(11) 98888-0001")
    checkout = make_checkout(customer: @customer)
    assert_equal "maria@exemplo.com.br", checkout.payer_email
    assert_equal "11988880001", checkout.payer_phone
  end
end

# Dados pessoais (07): o link guarda a cópia do pagador; sai na anonimização e entra na exportação do titular.
class PaymentsCheckoutsPrivacyTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    add_contact(@customer, "email", "maria@exemplo.com.br")
    @checkout = make_checkout(customer: @customer, pix: true)
  end

  test "a exportação do titular lista o link sem o endereço dele" do
    exported = Titular::Exporter.new(@customer).to_h
    link = exported[:links_de_pagamento].sole
    assert_equal [ "open", 99_900, "Maria Souza", "maria@exemplo.com.br" ], link.values_at(:situacao, :valor_centavos, :nome_do_pagador, :email_do_pagador)
    assert_not_includes exported.to_json, @checkout.token
  end

  test "a anonimização apaga a cópia do pagador do link e o cancela: o endereço deixa de abrir" do
    Titular::Anonymizer.new(actor: users(:joana), form: "request", reason: "pedido do titular").run(@alfa.id, [ @customer.id ])
    @checkout.reload
    assert_nil @checkout.payer_email
    assert_nil @checkout.payer_phone
    assert_empty @checkout.payer_address
    assert_not_equal "Maria Souza", @checkout.payer_name
    assert_not_equal "52998224725", @checkout.payer_document
    assert @checkout.state_canceled?
    assert_not @checkout.available?
    assert_not_equal "Maria Souza", @checkout.instruments.first.payer_name
  end
end
