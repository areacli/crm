require "application_system_test_case"

# Títulos do acordo no navegador (11, R221 a R244), nas abas da casca: a página do acordo efetivado, a ficha com os títulos de acordo e os renegociados, o
# cálculo da quitação, a quebra manual, o acordo quebrado, o arquivo de acordos e a simulação com crédito, sem rolagem horizontal.
class AgreementTitlesScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366) ])
    travel_back
    entrar_na_casca
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "a página do acordo efetivado mostra os títulos de acordo, calcula a quitação e quebra manualmente" do
    visit agreement_path(@agreement)
    assert_selector ".aba-raiz h1", text: /Acordo ACD-000001/, wait: 15
    assert_selector ".aba-raiz h2", text: "Títulos de acordo"
    assert_selector ".aba-raiz .datagrid-row a", text: "ACD-000001-03"

    mais_acoes "Calcular quitação"
    no_dialogo do
      find_field("Data da quitação").fill_in(with: (Date.current + 30).strftime("%d/%m/%Y"))
      find_field("Data da quitação").send_keys(:tab)
    end
    gravar_dialogo "Calcular quitação"
    assert_aviso(/Quitação calculada/)
    assert_selector ".aba-raiz li", text: /Quitação calculada para/, wait: 10

    mais_acoes "Quebrar o acordo"
    no_dialogo do
      fill_in "Motivo da quebra", with: "documento falso"
      check "Quebra por fraude"
    end
    gravar_dialogo "Quebrar o acordo"
    assert_selector ".aba-raiz aside", text: /Acordo quebrado em/, wait: 10
  end

  test "a ficha marca o título de acordo e o renegociado e a lista de acordos leva ao arquivo" do
    visitar_ficha(@customer)
    na_aba_interna { assert_selector ".datagrid-row .situacao", text: "Renegociado" }
    # Padrões de interface, revisões 27 e 38: a origem do título fica na janela dele, aberta pelo número.
    na_aba_interna { click_link Bill.where(customer: @customer).where.not(agreement_id: nil).order(:due_date).first.number }
    assert_selector ".janela-corpo section[aria-labelledby=cobranca-do-titulo] p", text: /Título de acordo ACD-000001/
    visit bill_path(Bill.where(customer: @customer).detect(&:renegotiated?))
    assert_selector ".janela-corpo section[aria-labelledby=cobranca-do-titulo] p", text: /Renegociado no acordo ACD-000001/, wait: 15

    visitar_lista agreements_path
    click_link "Ver o arquivo de acordos"
    assert_selector ".aba-raiz h1", text: "Arquivo de acordos"
    within(".aba-raiz .cabecalho-da-pagina") { click_link "Exportar" }
    no_dialogo { escolher "Forma", "Completo" }
    gravar_dialogo "Exportar"
    assert_aviso(/Arquivo de acordos exportado/)
    assert_selector ".aba-raiz .datagrid-row a", text: "Baixar", wait: 10
  end

  test "a simulação oferece o crédito do contrato e mostra o que falta da entrada" do
    other = make_user(@alfa, %w[negotiate_agreements])
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 4_366, reason: :excess)
    Agreement.where(id: @agreement.id).update_all(state: "canceled")
    AgreementBill.where(agreement_id: @agreement.id).update_all(held: false)
    PaymentPromise.delete_all
    Bill.where(id: [ @nf1.id, @nf2.id ]).update_all(status: "active")
    visit new_customer_agreement_simulation_path(@customer)
    assert_selector ".simulacao form[data-calculo]", wait: 15
    check "titulo-#{@nf1.id}"
    check "titulo-#{@nf2.id}"
    fill_in "Desconto em multa (%)", with: "50"
    fill_in "Desconto em juros (%)", with: "50"
    escolher "Parcelas", "4 parcelas"
    fill_in "Dia de vencimento das parcelas", with: "5"
    fill_in "Crédito do contrato a usar", with: "43,66"
    assert_selector ".estado-do-calculo[data-situacao=calculado]", wait: 10
    assert_selector ".simulacao-resultado dt", text: "Crédito do contrato usado na entrada"
    sem_rolagem_horizontal
    assert_not_nil other
  end
end
