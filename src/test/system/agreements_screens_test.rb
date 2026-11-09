require "application_system_test_case"

# Acordos no navegador (11), nas abas da casca: a simulação com cálculo à vista, a proposta, a página do acordo com o aceite em diálogo, a lista, os pendentes
# e a configuração; o termo é a página para imprimir, fora da casca, no axe.
class AgreementsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    @alfa.setting.update!(installment_method: "price", installment_rate_pct: 1.5)
    entrar_na_casca
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # A proposta nasce agora; o aceite do teste precisa ser depois da aprovação (o campo de data e hora só tem minutos), então a montagem recua duas horas.
  def backdate!(agreement)
    agreement.update_columns(created_at: 2.hours.ago, decided_at: 2.hours.ago)
  end

  def simulacao
    visit new_customer_agreement_simulation_path(@customer) # o endereço antigo leva à aba na casca (fase 4)
    assert_selector ".simulacao form[data-calculo]", wait: 15
    esperar_os_pedidos
  end

  def calculado = assert_selector(".estado-do-calculo[data-situacao=calculado]", text: /Calculado às/, wait: 10)

  test "a simulação recalcula à vista, a proposta é criada e abre numa aba, e a ficha e o termo mostram o acordo" do
    simulacao
    assert_selector ".estado-do-calculo", text: "Calculado com os dados da tela"
    assert_button "Criar proposta", disabled: false
    check "titulo-#{@nf1.id}"
    check "titulo-#{@nf2.id}"
    fill_in "Desconto em multa (%)", with: "50"
    fill_in "Desconto em juros (%)", with: "50"
    escolher "Parcelas", "4 parcelas"
    fill_in "Dia de vencimento das parcelas", with: "5"
    assert_selector ".estado-do-calculo", text: /Calculando/ # o período começa na primeira tecla
    calculado
    within(".simulacao-resultado") do
      assert_selector "h2", text: "Entrada e parcelas"
      assert_selector ".datagrid-row", text: "Parcela 4"
      assert_selector "dd", text: /R\$ \d/
    end
    sem_rolagem_horizontal

    click_button "Criar proposta"
    assert_aviso(/ACD-000001/)
    assert_selector "#abas .tabs-selected .tabs-title", text: "Acordo ACD-000001", wait: 10
    assert_selector ".aba-raiz a", text: "Registrar aceite"

    visitar_ficha(@customer, aba: "promessas")
    na_aba_interna { assert_selector "#acordos .datagrid-row", text: "ACD-000001" }
    aba_interna "Títulos"
    na_aba_interna { assert_selector ".datagrid-row .situacao", text: "Em proposta" }

    visit agreement_term_path(Agreement.sole)
    assert_selector "h1", text: "Termo de acordo ACD-000001"
    assert_acessivel
    sem_rolagem_horizontal
  end

  # Revisão 12: a tela abre pronta com zero concessão; a entrada acompanha o mínimo até a pessoa mexer nela, e o controle deslizante e o campo andam juntos.
  test "a simulação abre com zero concessão, e os controles acompanham a regra" do
    simulacao
    assert_checked_field "titulo-#{@nf1.id}"
    assert_checked_field "titulo-#{@nf2.id}"
    assert_field "Desconto em multa (%)", with: "0"
    assert_equal "1", find("input.textbox-value[name='agreement[installments]']", visible: :all).value
    inicial = find_field("Valor da entrada").value
    assert_match(/\A[\d.]+,\d{2}\z/, inicial)

    fill_in "Desconto em multa (%)", with: "100"
    calculado
    assert_not_equal inicial, find_field("Valor da entrada").value # sem mexer na entrada, ela acompanha o mínimo

    page.execute_script("const bloco = jQuery('#entrada-valor').closest('.valor-com-deslizante'); bloco.find('.trilho-do-deslizante > input').first().slider('setValue', 100000)")
    assert_field "Valor da entrada", with: "1.000,00"
    calculado
    within(".simulacao-resultado") { assert_selector "dd", text: "R$ 1.000,00" }

    fill_in "Desconto em juros (%)", with: "100"
    calculado
    assert_field "Valor da entrada", with: "1.000,00" # depois de mexer, a entrada não anda sozinha

    escolher "Parcelas", "0 (parcela única)"
    assert_no_field "Valor da entrada"
    assert_no_field "Dia de vencimento das parcelas"
    assert_field "Vencimento da parcela única"
    calculado
    within(".simulacao-resultado") { assert_selector "dt", text: "Parcela única" }

    escolher "Parcelas", "3 parcelas" # e dá para voltar
    assert_field "Valor da entrada"
    assert_field "Vencimento da entrada"
  end

  # A grade é medida na montagem: a largura da coluna muda depois (menu recolhido, janela) e a tabela não pode ficar cortada, nem esconder o que não coube.
  test "a tabela das parcelas acompanha a largura da coluna e rola quando não cabe" do
    simulacao
    escolher "Parcelas", "12 parcelas"
    calculado
    corpo = "document.querySelector('#simulacao .datagrid-view2 .datagrid-body')"
    antes = page.evaluate_script("#{corpo}.clientWidth")
    assert_operator page.evaluate_script("#{corpo}.scrollWidth"), :<=, antes

    find("#alternar-menu").click
    sleep 0.8
    assert_operator page.evaluate_script("#{corpo}.clientWidth"), :>, antes
    assert_operator page.evaluate_script("#{corpo}.scrollWidth"), :<=, page.evaluate_script("#{corpo}.clientWidth")

    page.execute_script("document.querySelector('#simulacao .tabela-em-grade').style.width = '320px'")
    sleep 0.6
    assert_equal "auto", page.evaluate_script("getComputedStyle(#{corpo}).overflowX"), "o que não cabe rola, em vez de sumir"
  end

  test "desconto acima do limite do perfil pede aprovação; o valor fora da faixa é recusado e não deixa criar a proposta" do
    simulacao
    assert_selector "#ajuda-desconto-principal", text: "Qualquer desconto aqui pede aprovação."
    fill_in "Desconto em principal (%)", with: "5"
    assert_selector ".simulacao-resultado .aviso", text: /a proposta nasce pendente/i, wait: 10
    calculado
    assert_button "Criar proposta", disabled: false
    fill_in "Desconto em principal (%)", with: "101"
    assert_selector ".simulacao-resultado [data-calculo=recusado]", wait: 10
    assert_button "Criar proposta", disabled: true
    assert_equal 0, Agreement.count
  end

  test "o aceite é registrado pelo diálogo da página do acordo e o acordo fica aguardando efetivação" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], user: users(:joana), down: nil, down_on: nil)
    backdate!(agreement)
    visit agreement_path(agreement)
    assert_selector ".aba-raiz h1", text: "Acordo #{agreement.number}", wait: 15
    click_link "Registrar aceite"
    no_dialogo do
      # Data e hora no `datetimebox` (dd/mm/aaaa hh:mm), digitadas como a pessoa faria.
      find_field("Data e hora da apresentação").fill_in(with: 1.hour.ago.strftime("%d/%m/%Y %H:%M"))
      find_field("Data e hora da apresentação").send_keys(:tab)
      find_field("Data e hora do aceite").fill_in(with: 30.minutes.ago.strftime("%d/%m/%Y %H:%M"))
      find_field("Data e hora do aceite").send_keys(:tab)
      fill_in "Comprovante (opcional)", with: "88213"
    end
    gravar_dialogo "Registrar aceite"

    assert_aviso(/Aceite do acordo ACD-000001 registrado/)
    assert_selector ".aba-raiz h2", text: "Aceite registrado"
    assert_selector ".aba-raiz .cabecalho-da-pagina .situacao", text: "Aguardando efetivação"
  end

  test "a lista de acordos e os pendentes, e o gestor aprova a pendente pela lista" do
    create_proposal(@customer, [ @nf1 ], user: users(:carlos), down: nil, down_on: nil)
    pending = create_proposal(@customer, [ @nf2 ], user: users(:carlos), discounts: { "fine" => 10_000, "interest" => 5_000 }, installments: 2, down: 20_000, down_on: nil)
    visitar_lista agreements_path
    assert_linhas_do_resultado 2

    visitar_lista pending_agreements_path
    assert_selector ".aba-raiz h1", text: "Acordos pendentes"
    assert_linhas_do_resultado 1
    within("[id='resultado']") { click_button "Aprovar", match: :first }
    assert_aviso(/Proposta #{pending.number} aprovada/)
    assert_selector "[id='resultado'] .vazio", wait: 10
  end

  test "a lista se refaz pelo evento do tempo real quando outra pessoa grava uma proposta, mantendo o filtro" do
    visitar_lista agreements_path
    assert_selector "[id='resultado'] .vazio", text: "Nenhuma proposta ou acordo com estes filtros."
    create_proposal(@customer, [ @nf1 ], user: users(:carlos), down: nil, down_on: nil)
    sleep 1.6 # a aba ignora o evento que chega logo depois de ela mesma se refazer
    simular_evento({ channel: "AgreementsChannel", tenant_id: @alfa.id }, { event: "agreements-changed" })
    assert_linhas_do_resultado 1
  end

  # Na SPA (fase 7), fora do axe (plano, D7).
  test "a aba Promessas e acordos, os parâmetros dos acordos e as políticas de pagamento abrem nas abas, sem rolar na horizontal" do
    visit settings_promises_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Promessas e acordos", wait: 15
    assert_selector ".aba-raiz h2", text: /Variáveis de acordo do enquadramento financeiro/
    assert_selector ".aba-raiz h2", text: /Limites de acordo por perfil/
    sem_rolagem_horizontal

    abrir_aba settings_tiers_path
    assert_selector ".aba-raiz h2", text: /\AParâmetros dos acordos — /, wait: 10
    sem_rolagem_horizontal

    abrir_aba settings_payment_policy_path
    assert_selector ".aba-raiz h2", text: /Crédito, pagamento e tolerância nos acordos/, wait: 10
    sem_rolagem_horizontal
  end

  test "a lista de clientes tem o filtro 'cidade não reconhecida'" do
    visit customers_path
    assert_selector ".lista .datagrid-row a", text: "Maria Souza"
    escolher "Cidade", "Cidade não reconhecida"
    esperar_os_pedidos
    assert_selector ".lista .datagrid-row a", text: "Maria Souza"
  end
end
