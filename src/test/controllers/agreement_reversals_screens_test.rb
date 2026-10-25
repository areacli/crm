require "test_helper"

# Telas da reversão, dos estornos à espera, do crédito por estado e do painel de acordos (11, R233, R239, R242, R243, R245), com V10.
class AgreementReversalsScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, id: "PIX-ENTRADA") ])
    @agreement.reload
  end

  teardown { travel_back }

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "R239: só quem administra acordos vê e usa 'Reverter o acordo'; os dois passos e a desistência pelas telas" do
    entrar(users(:carlos))
    get agreement_path(@agreement)
    assert_select "summary", text: "Reverter o acordo", count: 0
    post agreement_reversion_path(@agreement), params: { reversion: { reason: "x" } }
    assert_response :not_found
    delete session_path

    entrar(users(:joana))
    get agreement_path(@agreement)
    assert_select "summary", text: "Reverter o acordo"
    post agreement_reversion_path(@agreement), params: { reversion: { reason: "devedor errado" } }
    assert_redirected_to agreement_path(@agreement)
    assert_predicate @agreement.reload, :reversing?
    follow_redirect!
    assert_select "aside", text: /Em reversão desde/
    assert_select "button", text: "Concluir a reversão"

    delete agreement_reversion_path(@agreement)
    assert_not_predicate @agreement.reload, :reversing?
    post agreement_reversion_path(@agreement), params: { reversion: { reason: "de novo" } }
    patch agreement_reversion_path(@agreement)
    assert_predicate @agreement.reload, :state_canceled?
  end

  test "R239: a reversão sem motivo é recusada com a mensagem" do
    entrar(users(:joana))
    post agreement_reversion_path(@agreement), params: { reversion: { reason: " " } }

    assert_equal I18n.t("agreements.reversion.reason_required"), flash[:alert]
    assert_not_predicate @agreement.reload, :reversing?
  end

  test "R239, V10: a reversão de um acordo de outro credor responde 'não encontrado' e fica registrada" do
    entrar(users(:marta))
    assert_difference -> { AccessEvent.count } do
      post agreement_reversion_path(@agreement), params: { reversion: { reason: "x" } }
    end
    assert_response :not_found
    assert_not_predicate @agreement.reload, :reversing?
  end

  test "R233, R243: o estorno à espera aparece na lista do gestor e na página própria; o gestor decide com motivo e a opção indisponível não aparece" do
    Agreements::Reversion.new(users(:joana)).open!(@agreement, "teste")
    travel_day(Date.new(2026, 11, 20))
    pay_lines([ pay_line("ACD-000001-01", Date.new(2026, 11, 20), 5_000, id: "PIX-P1") ])
    travel_day(Date.new(2026, 11, 25))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-P1", "valor" => "50,00", "data_estorno" => "25/11/2026", "identificador_estorno" => "E1") ], kind: "reversals", confirm: true)
    wait = ReversalWait.sole

    entrar(users(:joana))
    get agreements_path
    assert_select "th", text: "Estorno à espera do gestor"
    get reversal_waits_path
    assert_response :success
    assert_select "h2", text: /Pagamento PIX-P1: R\$ 50,00/
    assert_select "input[type=radio][value=credit]"
    assert_select "input[type=radio][value=reopen]", count: 0
    patch reversal_wait_path(wait), params: { decision: { choice: "credit", note: " " } }
    assert_equal I18n.t("agreements.waits.note_required"), flash[:alert]
    patch reversal_wait_path(wait), params: { decision: { choice: "credit", note: "devolvido" } }
    assert_predicate wait.reload, :state_decided?
  end

  test "R233, V10: quem não administra acordos não vê a página dos estornos à espera nem decide" do
    entrar(users(:carlos))
    get reversal_waits_path
    assert_response :not_found
  end

  test "R239: o crédito aguardando alocação aparece na ficha por contrato, e o gestor o aloca em título do mesmo contrato" do
    Agreements::Reversion.new(users(:joana)).open!(@agreement, "erro")
    Agreements::Reversion.new(users(:joana)).conclude!(@agreement.reload)
    travel_day(Date.new(2026, 11, 20))
    entrar(users(:joana))
    get customer_path(@customer)
    assert_select "small", text: /aguardando alocação R\$ 343,66/
    assert_select "summary", text: /Alocar crédito aguardando alocação/
    post customer_credit_allocations_path(@customer), params: { credit_allocation: { contract_id: @nf1.contract_id, bill_id: @nf2.id, amount: "100,00" } }
    assert_redirected_to customer_path(@customer, anchor: "credito")
    assert_equal 24_366, @nf1.contract.credit_balances["awaiting"]
    assert_operator @nf2.reload.paid_cents, :>, 0, "encargos antes do principal (R226)"
  end

  test "R232b, AI2: 'Usar crédito' na ficha só para título de acordo ou de estorno e só para quem negocia" do
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 10_000, reason: :excess, occurred_at: Time.current)
    entrar(users(:carlos))
    get customer_path(@customer)
    assert_select "summary", text: /Usar crédito no título ACD-000001-\d+ \(disponível no contrato: R\$ 100,00\)/, minimum: 1
    bill = Bill.find_by!(number: "ACD-000001-01")
    post customer_credit_uses_path(@customer), params: { credit_use: { bill_id: bill.id, amount: "50,00" } }
    assert_equal 5_000, bill.reload.paid_cents
    assert_equal 5_000, @nf1.contract.credit_cents
    post customer_credit_uses_path(@customer), params: { credit_use: { bill_id: @nf1.id, amount: "10,00" } }
    assert_includes flash[:alert], "título de acordo ou de estorno"
  end

  test "R242: o painel mostra os acordos do credor: em acordo, aceitos, ativos, desconto concedido por componente e quem montou" do
    entrar(users(:joana))
    get root_path
    assert_response :success
    assert_select "h2", text: /Acordos — Escola Alfa/
    assert_select "dt", text: "Dos quais em acordo"
    assert_select "dd", text: /R\$ 1.200,00/
    assert_select "dd", text: /R\$ 36,27/
    assert_select "small", text: /multa R\$ 15,08/
    assert_select "small", text: /Carlos Lima/
  end
end
