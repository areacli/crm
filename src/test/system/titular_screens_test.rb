require "application_system_test_case"

# Direitos do titular no navegador (07): ficha com as janelas de exportar e anonimizar, a página para imprimir, a guarda de dados e o prazo,
# todos no axe, sem rolagem horizontal; a página de guarda se refaz sozinha pelo WebSocket quando a tarefa roda.
class TitularScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_full_customer(@alfa, ended_on: Date.current - 5.years + 12.days, code: "CT-7")
    @joao = make_full_customer(@alfa, ended_on: Date.current - 9.years, document: PaymentsHelper::JOAO, name: "João Retido")
    Titular::Retainer.new(users(:joana)).retain(@joao, "ação judicial nº 77")
    TaskRun.create!(tenant: @alfa, name: "data_retention", status: "succeeded", started_at: 2.hours.ago, finished_at: 2.hours.ago, processed: 2)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # As ações do titular ficam no menu "Mais ações" da barra de página e abrem num modal pequeno.
  def abrir_acao(nome)
    find("button.menu-de-linha[aria-label='Mais ações do cliente']").click
    click_link nome
    assert_selector "dialog#painel[open][data-variant=modal]"
  end

  test "a ficha com os modais de exportar e de anonimizar abertos passa no axe" do
    visit customer_path(@maria)
    abrir_acao "Exportar dados"
    assert_acessivel
    within("#painel") { click_button "Cancelar" }
    assert_no_selector "dialog[open]"
    abrir_acao "Anonimizar"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "exportar abre a página para imprimir, que passa no axe" do
    visit customer_path(@maria)
    abrir_acao "Exportar dados"
    within("#painel") do
      fill_in "Motivo", with: "pedido do titular, protocolo 123"
      click_button "Exportar dados"
    end
    assert_selector "h1", text: /Dados de Maria Souza mantidos por/
    assert_link "Baixar em JSON"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "anonimizar pela janela, digitando o documento, e a ficha passa a mostrar o aviso" do
    visit customer_path(@maria)
    abrir_acao "Anonimizar"
    within("#painel") do
      fill_in "Motivo", with: "pedido do titular, protocolo 123"
      fill_in "Documento do cliente", with: "529.982.247-25"
      click_button "Anonimizar cliente"
    end
    assert_text "Cliente anonimizado em"
    assert_equal "Cliente anonimizado nº #{@maria.id}", @maria.reload.name
    assert_acessivel
  end

  test "a página de guarda passa no axe e se refaz sozinha quando a tarefa roda" do
    visit data_retention_path
    assert_selector "h2", text: "Anonimização prevista nos próximos 30 dias"
    assert_selector "section[aria-labelledby=previstos] th", text: "Maria Souza"
    assert_selector "section[aria-labelledby=retidos] th", text: "João Retido"
    click_link "Reter", match: :first
    assert_selector "dialog#painel[open][data-variant=modal]"
    assert_acessivel
    find("dialog#painel button", text: "Cancelar").click
    sem_rolagem_horizontal

    # O evento do WebSocket refaz o trecho sem recarregar a página.
    assert_selector "section[aria-labelledby=execucoes] tbody tr", count: 1
    Titular::RetentionRun.new(@alfa).call
    assert_selector "section[aria-labelledby=execucoes] tbody tr", count: 2, wait: 10
  end

  test "o prazo de guarda na aba Dados do credor passa no axe" do
    visit settings_tenant_registry_path
    assert_selector "legend", text: "Prazo de guarda dos dados"
    fill_in "Prazo, em anos", with: "6"
    click_button "Salvar prazo de guarda"
    assert_text "Prazo de guarda de Escola Alfa salvo"
    assert_equal 6, @alfa.setting.reload.retention_years
    assert_acessivel
  end
end
