require "application_system_test_case"

# Reversão, estornos à espera, crédito por estado, título de estorno, acordo sobre acordo e o resumo de acordos no navegador (11, R233, R239, R242, R250), nas
# abas da casca: sem rolagem horizontal e com a aba se refazendo pelo WebSocket (sem polling).
class AgreementReversalsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, id: "PIX-ENTRADA") ])
    travel_back
    entrar_na_casca
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "o gestor reverte o acordo em dois passos: a marca, o crédito aguardando alocação na ficha e a alocação" do
    # A página do acordo está na SPA (fase 4): aba de registro, com as ações em diálogos presos a ela.
    visit agreement_path(@agreement)
    assert_selector ".aba-raiz h1", text: /Acordo ACD-000001/, wait: 15
    mais_acoes "Reverter o acordo"
    no_dialogo { fill_in "Motivo da reversão", with: "registrado no cliente errado" }
    gravar_dialogo "Abrir a reversão"
    assert_selector ".aba-raiz aside", text: /Em reversão desde/, wait: 10

    mais_acoes "Concluir a reversão"
    gravar_dialogo "Concluir a reversão"
    assert_selector ".aba-raiz aside", text: /Acordo cancelado/, wait: 10
    visitar_ficha(@customer, aba: "pagamentos")
    na_aba_interna do
      assert_selector "small", text: /aguardando alocação R\$ 343,66/
      click_link(text: /Alocar crédito aguardando alocação/)
    end
    no_dialogo { assert_selector "select, input", minimum: 1 }
  end

  test "a página dos estornos à espera mostra a idade, as opções e a decisão, e se refaz pelo WebSocket" do
    Agreements::Reversion.new(users(:joana)).open!(@agreement.reload, "teste")
    travel_day(Date.new(2026, 11, 20))
    pay_lines([ pay_line("ACD-000001-01", Date.new(2026, 11, 20), 5_000, id: "PIX-P1") ])
    travel_day(Date.new(2026, 11, 25))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-P1", "valor" => "50,00", "data_estorno" => "25/11/2026", "identificador_estorno" => "E1") ], kind: "reversals", confirm: true)
    travel_back

    # A lista está na SPA (fase 5): a decisão em diálogo, e a lista se refaz no fim.
    visitar_lista reversal_waits_path
    assert_selector ".aba-raiz h1", text: "Estornos à espera do gestor"
    assert_selector "[id='resultado'] .datagrid-row", text: /PIX-P1/
    assert_selector "[id='resultado'] .datagrid-row", text: "R$ 50,00"
    within("[id='resultado']") { click_link "Decidir" }
    no_dialogo do
      choose "Lançar no crédito do contrato"
      fill_in "Motivo da decisão", with: "devolvido pelo banco"
    end
    gravar_dialogo "Decidir"
    assert_selector ".aba-raiz h2", text: "Decididos há pouco", wait: 10
  end

  test "o painel traz o cartão de acordos do credor" do
    visit summary_path # o endereço antigo leva à aba do resumo na casca
    assert_selector ".aba-raiz h2", text: /\AAcordos/, wait: 15
    assert_selector ".aba-raiz dt", text: /Dos quais em acordo/
    sem_rolagem_horizontal
  end

  test "a ficha mostra o título de estorno com a marca e 'Usar crédito' o paga" do
    Agreements::Reversion # carrega o módulo
    extra = Agreements::ReversalTitles.create!(@agreement, items: [ { "bill_id" => @nf1.id, "component" => "principal", "cents" => 4_366 } ], contract: @nf1.contract, action_on: Date.current, processed_on: Date.current)
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 2_000, reason: :excess, occurred_at: Time.current)
    visit bill_path(extra) # o endereço antigo do título leva à casca, que o abre em janela
    assert_selector ".janela-corpo section[aria-labelledby=cobranca-do-titulo] p", text: /Título de estorno do acordo ACD-000001/, wait: 15
    visitar_ficha(@customer)
    na_aba_interna { linha_da_grade(extra.number).find(".menu-de-linha").click }
    find("[popover]:popover-open .botao", text: /Usar crédito/).click
    no_dialogo { fill_in "Valor a usar", with: "20,00" }
    gravar_dialogo "Usar crédito"
    assert_aviso(/R\$ 20,00 de crédito usados no título/)
  end

  test "a simulação aceita o título de um acordo quebrado e mostra os componentes herdados" do
    Agreements::Breaker.manual!(@agreement.reload, users(:joana), reason: "documento falso", fraud: true, today: Date.current)
    visit new_customer_agreement_simulation_path(@customer)
    assert_selector ".simulacao form[data-calculo]", wait: 15
    assert_selector "tr.detalhe-da-linha p", text: /Título de acordo ACD-000001/, visible: :all
    all("input[type=checkbox][id^=titulo-]:not([disabled])").map { |box| box[:id] }.each { |id| check id } # "só com todos" (M14): todos os títulos em aberto do acordo anterior
    fill_in "Desconto em juros do parcelamento herdados (%)", with: "0" if page.has_field?("Desconto em juros do parcelamento herdados (%)")
    escolher "Parcelas", "3 parcelas"
    fill_in "Dia de vencimento das parcelas", with: "5"
    assert_selector ".estado-do-calculo[data-situacao=calculado]", wait: 10
    assert_selector ".simulacao-resultado h2", text: "Entrada e parcelas"
    sem_rolagem_horizontal
  end
end
