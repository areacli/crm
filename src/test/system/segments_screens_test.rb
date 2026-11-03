require "application_system_test_case"

# Segmentos, enquadramento financeiro e índices no navegador (13, 08): editor em blocos com htmx e o "Conferir" pelo WebSocket, conferência do
# impacto em segundo plano, lista e ficha, e a tela de índices; todos no axe, sem rolagem horizontal.
class SegmentsSystemScreensTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @month = (Date.current - 2.months).beginning_of_month
    IndexRate::SERIES.each_with_index { |series, i| IndexRate.create!(series: series, month: @month, value: "0.#{i + 4}2", fetched_at: Time.current) }
    IndexRate.create!(series: "selic", month: Date.current.beginning_of_month, value: "0.61", partial: true, fetched_at: Time.current)
    IndexAdjustment.create!(tenant: @alfa, series: "igpm", month: @month, value: "1.52", reason: "valor da FGV", user: users(:joana), adjusted_at: Time.current)
    TaskRun.create!(name: "index_fetch", status: "succeeded", started_at: 2.hours.ago, finished_at: 2.hours.ago, processed: 4)
    make_tier(@alfa, "PF", person_type: "person")
    @contract = make_contract(@alfa, "CT-1", bills: [ { overdue: 40, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(51), "Maria Souza") ])
    recalc(@alfa)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "o editor de segmentos, o enquadramento, a conferência e a ficha passam no axe; a leitura e os erros aparecem enquanto escreve e o Conferir chega pelo WebSocket" do
    visit settings_segments_path
    assert_selector "h1", text: "Segmentos"
    assert_selector "th", text: "PF"
    assert_acessivel
    sem_rolagem_horizontal

    click_link "Criar segmento"
    assert_selector "h1", text: "Novo segmento"
    fill_in "Nome do segmento", with: "Atraso de 1 a 90"
    fill_in "Texto do segmento", with: "contratos\n  atraso entre 1 e 90\n  titulos vencidos 2"
    assert_selector "li[data-erro] p.erro", text: "Linha 3: vem uma comparação", wait: 10
    fill_in "Texto do segmento", with: "contratos\n  atraso entre 1 e 90"
    assert_selector "p.leitura strong", text: "Seleciona contratos em que o contrato tem atraso entre 1 dia e 90 dias.", wait: 10
    click_button "Conferir"
    assert_selector "#conferir", text: "Contando"
    perform_enqueued_jobs(only: SegmentProbeJob)
    assert_selector "#conferir", text: "Pega 1 contrato", wait: 10
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Salvar segmento"
    assert_text "Segmento \"Atraso de 1 a 90\" criado"

    visit settings_tiers_path
    assert_selector "h1", text: "Enquadramento financeiro"
    assert_acessivel
    click_link "Incluir segmento"
    assert_selector "dialog#painel[open]"
    select "Atraso de 1 a 90 — atraso entre 1 e 90", from: "Segmento"
    click_button "Conferir o impacto"
    assert_selector "h1", text: "Conferir o impacto"
    assert_text "Conferindo"
    perform_enqueued_jobs(only: TierReviewJob)
    assert_selector "h3", text: "Incluído no enquadramento: Atraso de 1 a 90"
    assert_text "Nenhum contrato muda de item", wait: 10
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Confirmar mudança"
    assert_text "Enquadramento financeiro de Escola Alfa atualizado"

    visit customers_path(q: "Maria")
    assert_selector "td", text: "PF"
    assert_acessivel
    visit customer_path(@contract.customers.first, aba: "historico")
    assert_selector "h2", text: "Histórico do enquadramento financeiro"
    assert_acessivel
    sem_rolagem_horizontal
    visit settings_segment_glossary_path
    assert_acessivel
  end

  test "a aba Índices passa no axe e se refaz sozinha pelo WebSocket quando a busca termina" do
    visit settings_indexes_path
    assert_selector "h1", text: "Índices do Banco Central"
    assert_selector "td", text: /Corrigido\s+1,52%/
    click_link "Editar índice", match: :first
    assert_selector "dialog#painel[open][data-variant=drawer]"
    assert_acessivel
    find("dialog#painel button", text: "Cancelar").click
    sem_rolagem_horizontal

    assert_selector "section[aria-labelledby=situacao] tbody tr", count: 1
    fake_bank(433 => [ [ @month.strftime("%d/%m/%Y"), "0.40" ] ])
    Indexes::Fetch.new.call
    assert_selector "section[aria-labelledby=situacao] tbody tr", count: 2, wait: 10
  end
end
