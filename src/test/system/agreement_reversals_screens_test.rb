require "application_system_test_case"

# Reversão, estornos à espera, crédito por estado, título de estorno, acordo sobre acordo e o painel de acordos no navegador (11, R233, R239, R242, R250): no axe, sem rolagem
# horizontal e com a tela se refazendo pelo WebSocket (sem polling).
class AgreementReversalsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, id: "PIX-ENTRADA") ])
    travel_back
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "o gestor reverte o acordo em dois passos: a marca, o crédito aguardando alocação na ficha e a alocação, no axe" do
    visit agreement_path(@agreement)
    find("button.menu-de-linha[aria-label='Mais ações do acordo']").click
    click_link "Reverter o acordo"
    assert_selector "dialog#painel[open][data-variant=modal]"
    fill_in "Motivo da reversão", with: "registrado no cliente errado"
    click_button "Abrir a reversão"
    assert_selector "aside", text: /Em reversão desde/, wait: 10
    find("button.menu-de-linha[aria-label='Mais ações do acordo']").click
    assert_selector "a", text: "Concluir a reversão"
    assert_acessivel
    sem_rolagem_horizontal

    click_link "Concluir a reversão"
    within("dialog#painel[open]") { click_button "Concluir a reversão" }
    assert_selector "aside", text: /Acordo cancelado/, wait: 10
    visit customer_path(@customer, aba: "pagamentos")
    assert_selector "small", text: /aguardando alocação R\$ 343,66/
    click_link(text: /Alocar crédito aguardando alocação/)
    assert_selector "dialog#painel[open][data-variant=modal]"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a página dos estornos à espera mostra a idade, as opções e a decisão, e se refaz pelo WebSocket" do
    Agreements::Reversion.new(users(:joana)).open!(@agreement.reload, "teste")
    travel_day(Date.new(2026, 11, 20))
    pay_lines([ pay_line("ACD-000001-01", Date.new(2026, 11, 20), 5_000, id: "PIX-P1") ])
    travel_day(Date.new(2026, 11, 25))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-P1", "valor" => "50,00", "data_estorno" => "25/11/2026", "identificador_estorno" => "E1") ], kind: "reversals", confirm: true)
    travel_back

    visit reversal_waits_path
    assert_selector "h1", text: "Estornos à espera do gestor"
    assert_selector "th", text: /PIX-P1/
    assert_selector "td", text: "R$ 50,00"
    assert_acessivel
    sem_rolagem_horizontal
    click_link "Decidir"
    assert_selector "dialog#painel[open][data-variant=modal]"
    choose "Lançar no crédito do contrato"
    fill_in "Motivo da decisão", with: "devolvido pelo banco"
    within("dialog#painel[open]") { click_button "Decidir" }
    assert_selector "h2", text: "Decididos há pouco", wait: 10
    assert_acessivel
  end

  test "o painel traz o cartão de acordos do credor" do
    visit root_path
    assert_selector "h2", text: /\AAcordos/
    assert_selector "dt", text: /Dos quais em acordo/
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a ficha mostra o título de estorno com a marca e 'Usar crédito' o paga" do
    Agreements::Reversion # carrega o módulo
    extra = Agreements::ReversalTitles.create!(@agreement, items: [ { "bill_id" => @nf1.id, "component" => "principal", "cents" => 4_366 } ], contract: @nf1.contract, action_on: Date.current, processed_on: Date.current)
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 2_000, reason: :excess, occurred_at: Time.current)
    visit customer_path(@customer)
    assert_selector "th small", text: /Título de estorno do acordo ACD-000001/
    find("button.menu-de-linha[aria-label='Ações do título #{extra.number}']").click
    click_link(text: /Usar crédito/)
    within("#painel") do
      fill_in "Valor a usar", with: "20,00"
      click_button "Usar crédito"
    end
    assert_selector "[role=status], .aviso", text: /R\$ 20,00 de crédito usados no título/
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a simulação aceita o título de um acordo quebrado e mostra os componentes herdados" do
    Agreements::Breaker.manual!(@agreement.reload, users(:joana), reason: "documento falso", fraud: true, today: Date.current)
    visit new_customer_agreement_simulation_path(@customer)
    assert_selector "th small", text: /título de acordo ACD-000001/
    all("input[type=checkbox][id^=titulo-]:not([disabled])").map { |box| box[:id] }.each { |id| check id } # "só com todos" (M14): todos os títulos em aberto do acordo anterior
    fill_in "Desconto em juros do parcelamento herdados (%)", with: "0" if page.has_field?("Desconto em juros do parcelamento herdados (%)")
    fill_in "Parcelas", with: "3"
    fill_in "Dia de vencimento das parcelas", with: "5"
    assert_selector "#simulacao h2", text: "Entrada e parcelas", wait: 10
    page.execute_script("window.scrollTo(0, 0)") # o cabeçalho fixo cobriria o item do menu lateral na medição de alvo do axe
    assert_acessivel
    sem_rolagem_horizontal
  end
end
