require "application_system_test_case"

# Acordos no navegador (11): a simulação que se refaz pelo htmx, a proposta, a página do acordo, o termo, o aceite, a lista, os pendentes e a configuração,
# todos no axe e sem rolagem horizontal.
class AgreementsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    @alfa.setting.update!(installment_method: "price", installment_rate_pct: 1.5)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def wait_htmx = assert_no_selector(".htmx-request")

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # A proposta nasce agora; o aceite do teste precisa ser depois da aprovação (o campo de data e hora só tem minutos), então a montagem recua duas horas.
  def backdate!(agreement)
    agreement.update_columns(created_at: 2.hours.ago, decided_at: 2.hours.ago)
  end

  test "a simulação mostra a base e as parcelas, a proposta é criada e a ficha, a página do acordo e o termo passam no axe" do
    visit customer_path(@customer)
    click_link "Simular acordo"
    assert_selector "h1", text: "Simular acordo"
    check "titulo-#{@nf1.id}"
    check "titulo-#{@nf2.id}"
    fill_in "Desconto em multa (%)", with: "50"
    fill_in "Desconto em juros (%)", with: "50"
    fill_in "Parcelas", with: "4"
    fill_in "Dia de vencimento das parcelas", with: "5"
    wait_htmx
    assert_selector "#simulacao h2", text: "Entrada e parcelas"
    assert_selector "#simulacao th", text: "Parcela 4"
    assert_selector "#simulacao dd", text: /R\$ \d/
    assert_acessivel
    sem_rolagem_horizontal

    click_button "Criar proposta"
    assert_selector "h1", text: /Acordo ACD-000001/
    assert_selector "h2", text: "Registrar o aceite"
    assert_acessivel
    sem_rolagem_horizontal

    visit customer_path(@customer)
    assert_selector "ul.promessas li", text: /1 proposta aguardando aceite/
    assert_selector "th small", text: /Em proposta ACD-000001/
    assert_acessivel
    sem_rolagem_horizontal

    visit agreement_term_path(Agreement.sole)
    assert_selector "h1", text: "Termo de acordo ACD-000001"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a simulação volta com a mensagem do limite quando o desconto passa do teto" do
    visit new_customer_agreement_simulation_path(@customer)
    check "titulo-#{@nf1.id}"
    fill_in "Desconto em principal (%)", with: "5"
    wait_htmx
    assert_selector "#simulacao aside", text: /não permite desconto em principal/i
    click_button "Criar proposta"
    assert_selector "aside[role=alert]", text: "O segmento não permite desconto em principal."
    assert_equal 0, Agreement.count
    assert_acessivel
  end

  test "o aceite é registrado pela página do acordo e o acordo fica aguardando efetivação" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], user: users(:joana), down: nil, down_on: nil)
    backdate!(agreement)
    visit agreement_path(agreement)
    # Campo de data e hora do navegador: grava o valor direto, como quem escolhe no calendário.
    page.execute_script("document.getElementById('acceptance_presented_at').value = '#{1.hour.ago.strftime('%Y-%m-%dT%H:%M')}'")
    page.execute_script("document.getElementById('acceptance_accepted_at').value = '#{30.minutes.ago.strftime('%Y-%m-%dT%H:%M')}'")
    fill_in "Comprovante (opcional)", with: "88213"
    click_button "Registrar aceite"

    assert_selector "aside[role=status]", text: /Aceite do acordo ACD-000001 registrado/
    assert_selector "h2", text: "Aceite registrado"
    assert_selector "h1 .situacao", text: "Aguardando efetivação"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a lista de acordos e os pendentes passam no axe, e o gestor aprova a pendente" do
    create_proposal(@customer, [ @nf1 ], user: users(:carlos), down: nil, down_on: nil)
    pending = create_proposal(@customer, [ @nf2 ], user: users(:carlos), discounts: { "fine" => 10_000, "interest" => 5_000 }, installments: 2, down: 20_000, down_on: nil)
    visit agreements_path
    assert_selector "tbody tr", count: 2
    assert_acessivel
    sem_rolagem_horizontal

    click_link "Acordos pendentes (1)"
    assert_selector "h1", text: "Acordos pendentes"
    assert_selector "tbody tr", count: 1
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Aprovar proposta"
    assert_selector "aside[role=status]", text: /Proposta #{pending.number} aprovada/
  end

  test "a lista se refaz sozinha pelo WebSocket quando outra pessoa grava uma proposta" do
    visit agreements_path
    assert_selector ".vazio", text: "Nenhuma proposta ou acordo com estes filtros."
    create_proposal(@customer, [ @nf1 ], user: users(:carlos), down: nil, down_on: nil)
    assert_selector "tbody tr", count: 1, wait: 10
  end

  test "a aba Promessas e acordos, os parâmetros dos acordos e as políticas de pagamento passam no axe" do
    visit settings_promises_path
    assert_selector "h1", text: "Promessas e acordos"
    assert_selector "h2", text: /Variáveis de acordo dos segmentos/
    assert_selector "h2", text: /Limites de acordo por perfil/
    assert_acessivel
    sem_rolagem_horizontal

    visit settings_segments_path
    assert_selector "legend", text: "Parâmetros dos acordos do credor"
    assert_acessivel
    sem_rolagem_horizontal

    visit settings_payment_policy_path
    assert_selector "h2", text: /Crédito, pagamento e tolerância nos acordos/
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a lista de clientes tem o filtro 'cidade não reconhecida'" do
    visit customers_path
    assert_selector "label", text: "Cidade"
    select "Cidade não reconhecida", from: "Cidade"
    assert_selector "tbody a", text: "Maria Souza"
    assert_acessivel
  end
end
