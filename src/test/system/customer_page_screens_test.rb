require "application_system_test_case"

# Ficha do cliente (padrões de interface, revisão 21) e menu lateral (design system, revisão 7): o contrato escolhido recorta a página inteira,
# a tabela de contratos mostra as operações que cobram cada um, a tabela de títulos cabe sem rolagem horizontal a 1440 px com o menu aberto,
# e o menu se esconde e se mostra pelo botão do cabeçalho, com a escolha valendo nas próximas páginas.
class CustomerPageScreensSystemTest < ApplicationSystemTestCase
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
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1")
    assert_selector "header .usuario"
  end

  def sem_rolagem_horizontal(seletor = ".tabela")
    page.evaluate_script("Array.from(document.querySelectorAll('#{seletor}')).every((el) => el.scrollWidth <= el.clientWidth + 1)") &&
      !page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end

  test "o contrato escolhido recorta a ficha e a coluna Operações mostra quem cobra cada contrato" do
    visit customer_path(@maria)
    # Revisão 28: o cartão Contratos fica antes das abas e é o filtro; sem contrato escolhido, nenhuma linha marcada.
    assert_selector "#contratos + nav.abas"
    assert_no_selector "#contratos tr[data-atual]"
    assert_no_selector "#contratos a", text: "Ver todos os contratos"
    assert_selector "tbody th", text: "CT-PRIMEIRO-0"
    assert_selector "tbody th", text: "CT-SEGUNDO-0"
    assert_selector "th", text: "Operações"
    assert_selector "ul.operacoes-do-contrato .situacao", text: "Recupera"
    assert_selector "ul.operacoes-do-contrato .situacao", text: "Cobra"
    # Revisão 23: só a etiqueta na tabela; a linha do tempo da lateral tem as duas entradas, a mais recente (Cobra, ontem) em cima.
    assert_no_selector "ul.operacoes-do-contrato small"
    assert_selector "ol.linha-do-tempo li[data-evento=entrada]", count: 2
    assert_selector "ol.linha-do-tempo li:first-child", text: /Entrada.*Cobra.*Contrato CT-PRIMEIRO · vencidas · à mão/m
    # Uma etiqueta por operação, mesmo com mais de uma distribuição dela no contrato (o contrato e o cliente).
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: Operation.find_by!(short_name: "Recupera"), customer: @maria, exposure: "all",
                                                             starts_on: Date.current - 2)
    visit customer_path(@maria)
    assert_selector "ul.operacoes-do-contrato .situacao", text: "Recupera", count: 2 # CT-PRIMEIRO e CT-SEGUNDO, uma vez cada
    assert_acessivel
    larguras = page.evaluate_script("Array.from(document.querySelectorAll('.tabela')).map((el) => [el.querySelector('caption')?.textContent, el.scrollWidth, el.clientWidth])")
    assert sem_rolagem_horizontal, "a ficha rola na horizontal a 1440 px com o menu aberto: #{larguras.inspect}"

    find("#contratos a[aria-label='Filtrar a ficha pelo contrato CT-SEGUNDO']").click
    assert_selector ".cabecalho-da-pagina .situacao", text: "Contrato CT-SEGUNDO"
    assert_selector "tbody th", text: "CT-SEGUNDO-0"
    assert_no_selector "tbody th", text: "CT-PRIMEIRO-0"
    within("section[aria-labelledby=titulos]") { assert_no_selector "thead th", text: /\AContrato\z/ }
    # O contrato escolhido passa de uma aba a outra.
    within("nav.abas") { click_link "Acionamentos" }
    assert_selector "#contratos tr[data-atual] a[aria-current='true']", text: "CT-SEGUNDO"
    assert_selector "#contratos tbody tr:not(.detalhe-da-linha)", count: 2 # o cartão continua com todos os contratos
    assert_includes page.current_url, "contrato=#{@second.id}"
    click_link "Ver todos os contratos"
    assert_no_selector ".cabecalho-da-pagina .situacao", text: "Contrato CT-SEGUNDO"
  end

  test "na ficha o menu começa recolhido e lembra a escolha à parte; nas outras páginas vale a escolha delas" do
    visit customer_path(@maria)
    assert_no_selector "body > nav", visible: true
    assert_selector "button[data-alternar-menu][aria-expanded='false']"
    assert sem_rolagem_horizontal
    find("button[data-alternar-menu][aria-label='Mostrar o menu']").click
    assert_selector "body > nav", visible: true

    # Mostrado na ficha, continua mostrado na próxima ficha, também quando se chega a ela pelo hx-boost.
    visit customers_path
    assert_selector "body > nav", visible: true
    find("button[data-alternar-menu][aria-label='Esconder o menu']").click
    assert_no_selector "body > nav", visible: true
    click_link "Maria Duas Contas"
    assert_selector "h1", text: "Maria Duas Contas"
    assert_selector "body > nav", visible: true
    find("button[data-alternar-menu][aria-label='Esconder o menu']").click
    visit customer_path(@maria)
    assert_no_selector "body > nav", visible: true
    # A lista continua com a escolha dela (recolhido), e o hx-boost de volta à lista a respeita.
    visit customers_path
    assert_no_selector "body > nav", visible: true
    assert_acessivel
  end

  test "a linha do tempo filtra por tipo e pagina sem recarregar a ficha" do
    12.times { |index| insert_attempt(@maria, contacted_at: (index + 1).hours.ago) }
    visit customer_path(@maria)
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
    assert_no_current_path(/linha=/)
    assert_acessivel
  end

  test "cada título ocupa uma linha, sem detalhe; o número leva à página do título (padrões de interface, revisão 27)" do
    Bill.where(contract: [ @first, @second ]).find_each do |bill|
      BillValuation.create!(bill_id: bill.id, tenant: @alfa, principal_cents: bill.amount_cents, corrected_principal_cents: bill.amount_cents, fine_cents: 100,
                            interest_cents: 200, fees_cents: 0, total_cents: bill.amount_cents + 300, calculated_on: Date.current)
    end
    visit customer_path(@maria)
    within("section[aria-labelledby=titulos]") do
      assert_no_selector "button[data-alternar-detalhe]"
      assert_no_selector "tr.detalhe-da-linha", visible: :all
      alturas = page.evaluate_script("Array.from(document.querySelectorAll('section[aria-labelledby=titulos] tbody tr')).map((tr) => tr.getBoundingClientRect().height)")
      assert alturas.all? { |altura| altura <= 37 }, "uma linha de título tem mais de uma linha de texto: #{alturas.inspect}"
      click_link "CT-PRIMEIRO-0"
    end
    assert_selector "h1", text: "Título CT-PRIMEIRO-0"
    assert_selector "dl.composicao dt", text: "Principal corrigido"
    assert_acessivel
  end
end
