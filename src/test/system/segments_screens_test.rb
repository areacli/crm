require "application_system_test_case"

# Segmentos e índices no navegador (08): abas, criar com conferência, tela de índices com a busca manual e o evento do WebSocket; todos no axe,
# sem rolagem horizontal.
class SegmentsSystemScreensTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @month = (Date.current - 2.months).beginning_of_month
    IndexRate::SERIES.each_with_index { |series, i| IndexRate.create!(series: series, month: @month, value: "0.#{i + 4}2", fetched_at: Time.current) }
    IndexRate.create!(series: "selic", month: Date.current.beginning_of_month, value: "0.61", partial: true, fetched_at: Time.current)
    IndexAdjustment.create!(tenant: @alfa, series: "igpm", month: @month, value: "1.52", reason: "valor da FGV", user: users(:joana), adjusted_at: Time.current)
    TaskRun.create!(name: "index_fetch", status: "succeeded", started_at: 2.hours.ago, finished_at: 2.hours.ago, processed: 4)
    make_segment(@alfa, "PF", person_type: "person")
    @contract = make_contract(@alfa, "CT-1", bills: [ { overdue: 40, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(51), "Maria Souza") ])
    recalc(@alfa)
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "a aba Segmentos, o formulário, a conferência e a ficha passam no axe" do
    visit settings_segments_path
    assert_selector "h1", text: "Segmentos"
    assert_selector "th", text: "PF"
    assert_acessivel
    sem_rolagem_horizontal

    click_link "Criar segmento"
    assert_selector "h1", text: "Novo segmento"
    fill_in "Nome", with: "Varejo PF recente"
    fill_in "segment_min_overdue_days", with: "1"
    fill_in "segment_max_overdue_days", with: "90"
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Conferir mudança"
    assert_selector "h1", text: "Conferir mudança nos segmentos"
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Confirmar mudança nos segmentos"
    assert_text "Segmentos de Escola Alfa atualizados"
    assert_selector "th", text: "Varejo PF recente"

    visit customers_path(q: "Maria")
    assert_selector "td", text: "PF"
    assert_acessivel
    visit customer_path(@contract.customers.first)
    assert_selector "h2", text: "Histórico de segmento"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "a aba Índices passa no axe e se refaz sozinha pelo WebSocket quando a busca termina" do
    visit settings_indexes_path
    assert_selector "h1", text: "Índices do Banco Central"
    assert_text "corrigido: 1,52%"
    find("summary", text: "Corrigir índice").click
    assert_acessivel
    sem_rolagem_horizontal

    assert_selector "section[aria-labelledby=situacao] tbody tr", count: 1
    fake_bank(433 => [ [ @month.strftime("%d/%m/%Y"), "0.40" ] ])
    Indexes::Fetch.new.call
    assert_selector "section[aria-labelledby=situacao] tbody tr", count: 2, wait: 10
  end
end
