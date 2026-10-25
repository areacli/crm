require "application_system_test_case"

# Títulos do acordo no navegador (11, R221 a R244): a página do acordo efetivado, a ficha com os títulos de acordo e os renegociados, o cálculo da quitação, a quebra manual, o acordo
# quebrado, o arquivo de acordos e a simulação com crédito; no axe e sem rolagem horizontal.
class AgreementTitlesScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366) ])
    travel_back
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "a página do acordo efetivado mostra os títulos de acordo, calcula a quitação e quebra manualmente, no axe" do
    visit agreement_path(@agreement)
    assert_selector "h1", text: /Acordo ACD-000001/
    assert_selector "h2", text: "Títulos de acordo"
    assert_selector "th a", text: "ACD-000001-03"
    assert_acessivel
    sem_rolagem_horizontal

    find("summary", text: "Calcular quitação").click
    fill_in "Data da quitação", with: (Date.current + 30).iso8601
    click_button "Calcular quitação"
    assert_selector "li", text: /Quitação calculada para/
    assert_acessivel

    find("summary", text: "Quebrar o acordo").click
    fill_in "Motivo da quebra", with: "documento falso"
    check "Quebra por fraude"
    click_button "Quebrar o acordo"
    assert_selector "aside", text: /Acordo quebrado em/
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a ficha marca o título de acordo e o renegociado e a lista de acordos leva ao arquivo" do
    visit customer_path(@customer)
    assert_selector "th small", text: /Título de acordo ACD-000001/
    assert_selector "th small", text: /Renegociado no acordo ACD-000001/
    assert_selector "td .situacao", text: "Renegociado"
    assert_acessivel
    sem_rolagem_horizontal

    visit agreements_path
    click_link "Arquivo de acordos"
    assert_selector "h1", text: "Arquivo de acordos"
    select "Completo", from: "Forma"
    click_button "Exportar"
    assert_selector "[role=status], .aviso", text: /Arquivo de acordos exportado/
    assert_selector "td a", text: "Baixar"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a simulação oferece o crédito do contrato e mostra o que falta da entrada" do
    other = make_user(@alfa, %w[negotiate_agreements])
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 4_366, reason: :excess)
    Agreement.where(id: @agreement.id).update_all(state: "canceled")
    AgreementBill.where(agreement_id: @agreement.id).update_all(held: false)
    PaymentPromise.delete_all
    Bill.where(id: [ @nf1.id, @nf2.id ]).update_all(status: "active")
    visit new_customer_agreement_simulation_path(@customer)
    check "titulo-#{@nf1.id}"
    check "titulo-#{@nf2.id}"
    fill_in "Desconto em multa (%)", with: "50"
    fill_in "Desconto em juros (%)", with: "50"
    fill_in "Parcelas", with: "4"
    fill_in "Dia de vencimento das parcelas", with: "5"
    fill_in "Crédito do contrato a usar", with: "43,66"
    assert_selector "#simulacao dt", text: "Crédito do contrato usado na entrada"
    assert_acessivel
    sem_rolagem_horizontal
    assert_not_nil other
  end
end
