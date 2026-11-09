require "application_system_test_case"

# Ficha do cliente na SPA (padrões de interface, revisões 21, 27 e 38; fase 3 do port, decisão 0028): o contrato escolhido recorta a aba inteira, a grade de contratos
# mostra as operações que cobram cada um, a de títulos cabe sem rolar de lado a 1440 px com o menu aberto, e o número do título abre a janela dele.
class CustomerPageScreensSystemTest < ApplicationSystemTestCase
  include SpaTestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = customer_of(@alfa, FakeData.cpf(801), "Maria Duas Contas")
    @first = make_contract(@alfa, "CT-PRIMEIRO", customers: [ @maria ], bills: [ { overdue: 40, cents: 120_000 }, { overdue: 10, cents: 33_000 } ])
    @second = make_contract(@alfa, "CT-SEGUNDO", customers: [ @maria ], bills: [ { overdue: 200, cents: 987_654_32 } ])
    recupera = make_operation(@alfa)
    cobra = make_operation(@alfa, short_name: "Cobra", cnpj: "55777888000165")
    distributor = Distributions::Distributor.new(users(:joana))
    # Sem exclusividade, um contrato pode ser cobrado por N operações ao mesmo tempo.
    @alfa.setting.update!(operation_exclusive: false)
    distributor.distribute(tenant: @alfa, operation: recupera, contract: @first, exposure: "all", starts_on: Date.current - 3)
    distributor.distribute(tenant: @alfa, operation: cobra, contract: @first, exposure: "overdue", starts_on: Date.current - 1)
    entrar_na_casca
  end

  def sem_rolagem_horizontal(seletor)
    page.evaluate_script("Array.from(document.querySelectorAll(arguments[0])).every((el) => el.scrollWidth <= el.clientWidth + 1)", seletor)
  end

  test "o endereço antigo da ficha abre a aba na casca" do
    visit customer_path(@maria, aba: "acionamentos")
    assert_selector "#abas .tabs-title", text: "Maria Duas Contas"
    assert_selector ".abas-internas .tabs-selected", text: "Acionamentos"
    assert_equal "#/clientes/#{@maria.id}?aba=acionamentos", page.evaluate_script("location.hash")
  end

  test "o contrato escolhido recorta a ficha e a coluna Operações mostra quem cobra cada contrato" do
    abrir_ficha(@maria)
    # Revisão 28: o cartão Contratos fica antes das abas e é o filtro; sem contrato escolhido, nenhuma linha marcada.
    within("#contratos") do
      assert_no_selector "tr.linha-atual"
      assert_no_link "Ver todos os contratos"
      assert_selector ".datagrid-row", text: "CT-PRIMEIRO"
      assert_selector ".datagrid-row", text: "CT-SEGUNDO"
      assert_selector ".datagrid-header", text: "Operações"
      assert_selector "ul.operacoes-do-contrato .situacao", text: "Recupera"
      assert_selector "ul.operacoes-do-contrato .situacao", text: "Cobra"
      assert_no_selector "ul.operacoes-do-contrato small"
    end
    # Revisão 23: a linha do tempo da lateral tem as duas entradas, a mais recente (Cobra, ontem) em cima.
    assert_selector "ol.linha-do-tempo li[data-evento=entrada]", count: 2
    assert_selector "ol.linha-do-tempo li:first-child", text: /Entrada.*Cobra.*Contrato CT-PRIMEIRO · vencidas · à mão/m
    na_aba_interna do
      larguras = page.evaluate_script("[...document.querySelectorAll('.abas-internas .datagrid-view2 .datagrid-header td[field]')].filter((td) => td.offsetParent).map((td) => [td.textContent.trim(), td.offsetWidth])")
      assert sem_rolagem_horizontal(".abas-internas .datagrid-view2 .datagrid-body"), "a grade de títulos rola de lado a 1440 px com o menu aberto: #{larguras.inspect}"
    end

    na_aba_interna do
      assert_selector ".datagrid-row", text: "CT-PRIMEIRO-0"
      assert_selector ".datagrid-row", text: "CT-SEGUNDO-0"
    end
    within("#contratos") { click_link "CT-SEGUNDO" }
    assert_selector ".aba-raiz .cabecalho-da-pagina .situacao", text: "Contrato CT-SEGUNDO"
    esperar_os_pedidos
    na_aba_interna do
      assert_selector ".datagrid-row", text: "CT-SEGUNDO-0"
      assert_no_selector ".datagrid-row", text: "CT-PRIMEIRO-0"
      assert_no_selector ".datagrid-header td", text: /\AContrato\z/
    end
    # O contrato escolhido passa de uma aba interna a outra, e o cartão continua com todos os contratos.
    aba_interna "Acionamentos"
    within("#contratos") do
      assert_selector "tr.linha-atual a[aria-current='true']", text: "CT-SEGUNDO"
      assert_selector ".datagrid-view2 tr.datagrid-row", count: 2
    end
    assert_includes page.evaluate_script("location.hash"), "contrato=#{@second.id}"
    click_link "Ver todos os contratos"
    assert_no_selector ".aba-raiz .cabecalho-da-pagina .situacao", text: "Contrato CT-SEGUNDO"
  end

  test "o detalhe da linha abre pela seta e pela seta do cabeçalho (P26)" do
    abrir_ficha(@maria)
    within("#contratos") do
      assert_no_text "Clientes do contrato: Maria Duas Contas"
      find(".datagrid-view1 tr.datagrid-row", match: :first).find(".datagrid-row-expander").click
      assert_text "Clientes do contrato: Maria Duas Contas"
      find(".datagrid-header [aria-label='Mostrar os detalhes de todas as linhas']").click
      assert_selector ".datagrid-row-detail", text: "Clientes do contrato", count: 2
    end
  end

  test "a linha do tempo filtra por tipo e pagina sem recarregar a ficha" do
    12.times { |index| insert_attempt(@maria, contacted_at: (index + 1).hours.ago) }
    abrir_ficha(@maria)
    page.execute_script("document.querySelector('.aba-raiz .ficha').dataset.marca = 'antes'")
    within("#linha-do-tempo") do
      assert_selector "ol.linha-do-tempo li", count: 10
      assert_text "1 de 2"
      click_link "Próxima"
      assert_text "2 de 2"
      assert_selector "ol.linha-do-tempo li", count: 4
      click_link "Distribuição"
      assert_selector "ol.linha-do-tempo li[data-evento=entrada]", count: 2
      assert_no_selector "ol.linha-do-tempo li[data-evento=atendimento]"
      assert_selector ".filtro-em-pilulas a[aria-current='true']", text: "Distribuição"
    end
    assert_selector ".aba-raiz .ficha[data-marca='antes']"
  end

  test "cada título ocupa uma linha, sem detalhe; o número abre a janela do título (padrões de interface, revisões 27 e 38)" do
    Bill.where(contract: [ @first, @second ]).find_each do |bill|
      BillValuation.create!(bill_id: bill.id, tenant: @alfa, principal_cents: bill.amount_cents, corrected_principal_cents: bill.amount_cents, fine_cents: 100,
                            interest_cents: 200, fees_cents: 0, total_cents: bill.amount_cents + 300, calculated_on: Date.current)
    end
    abrir_ficha(@maria)
    na_aba_interna do
      assert_no_selector ".datagrid-row-expander"
      alturas = page.evaluate_script("Array.from(document.querySelectorAll('.abas-internas .datagrid-view2 tr.datagrid-row')).filter((tr) => tr.offsetParent).map((tr) => tr.getBoundingClientRect().height)")
      assert alturas.all? { |altura| altura <= 37 }, "uma linha de título tem mais de uma linha de texto: #{alturas.inspect}"
      click_link "CT-PRIMEIRO-0"
    end
    assert_selector ".window .panel-title", text: "Título CT-PRIMEIRO-0"
    assert_selector ".janela-corpo dl.composicao dt", text: "Principal corrigido"
  end
end
