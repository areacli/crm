require "application_system_test_case"

# Segmentos, enquadramento financeiro e índices no navegador (13, 08), na SPA (fase 7): o editor com a leitura à vista e o "Conferir" pelo WebSocket, a conferência
# do impacto em segundo plano na própria aba, o glossário em janela e a tela de índices, sem rolagem horizontal.
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
    entrar_na_casca users(:joana)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def segmentos_do_alfa = { channel: "SegmentsChannel", tenant_id: @alfa.id }

  # Na SPA (fase 7 do port): o editor é uma aba própria, com a leitura como cálculo à vista (design system, 7.2), e a conferência do impacto ocupa a aba de onde
  # saiu. O axe saiu da área interna (plano, D7); o teste não tem WebSocket entre o servidor e o navegador, e o aviso do canal é entregue por `simular_evento`.
  test "o editor de segmentos, o enquadramento e a conferência abrem nas abas; a leitura aparece enquanto escreve, o Salvar espera o texto sem erro e o Conferir chega pelo WebSocket" do
    abrir_aba settings_segments_path
    assert_selector ".aba-raiz h1", text: "Segmentos", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "PF"
    sem_rolagem_horizontal

    within(".aba-raiz") { click_link "Criar segmento", match: :first }
    assert_selector ".aba-raiz h1", text: "Novo segmento", wait: 10
    assert_button "Salvar segmento", disabled: true # sem texto, nada a salvar
    fill_in "Nome do segmento", with: "Atraso de 1 a 90"
    fill_in "Texto do segmento", with: "contratos\n  atraso entre 1 e 90\n  titulos vencidos 2"
    assert_selector "li[data-erro] p.erro", text: "Linha 3: vem uma comparação", wait: 10
    assert_button "Salvar segmento", disabled: true
    fill_in "Texto do segmento", with: "contratos\n  atraso entre 1 e 90"
    assert_selector "p.leitura strong", text: "Seleciona contratos em que o contrato tem atraso entre 1 dia e 90 dias.", wait: 10
    assert_selector ".estado-do-calculo[data-situacao=calculado]"
    assert_button "Salvar segmento", disabled: false

    click_button "Conferir"
    assert_selector "[data-conferir]", text: "Contando", wait: 10
    perform_enqueued_jobs(only: SegmentProbeJob)
    simular_evento(segmentos_do_alfa, { event: "segment-probe-ready" })
    assert_selector "[data-conferir]", text: "Pega 1 contrato", wait: 10
    assert_field "Texto do segmento", with: "contratos\n  atraso entre 1 e 90" # o aviso refaz só o resultado, não o editor
    sem_rolagem_horizontal
    click_button "Salvar segmento"
    assert_aviso "Segmento \"Atraso de 1 a 90\" criado"
    assert_selector ".aba-raiz h1", text: "Segmentos", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Atraso de 1 a 90"

    abrir_aba settings_tiers_path
    assert_selector ".aba-raiz h1", text: "Enquadramento financeiro", wait: 10
    find(".aba-raiz .botao", text: "Incluir segmento", match: :first).click
    no_dialogo { escolher "Segmento", "Atraso de 1 a 90" }
    gravar_dialogo "Conferir o impacto"
    assert_selector ".aba-raiz h1", text: "Conferir o impacto", wait: 10
    assert_text "Conferindo"
    perform_enqueued_jobs(only: TierReviewJob)
    simular_evento(segmentos_do_alfa, { event: "tier-review-ready" })
    assert_selector "h3", text: "Incluído no enquadramento: Atraso de 1 a 90", wait: 10
    assert_text "Nenhum contrato muda de item"
    sem_rolagem_horizontal
    click_button "Confirmar mudança"
    assert_aviso "Enquadramento financeiro de Escola Alfa atualizado"
    assert_selector ".aba-raiz h1", text: "Enquadramento financeiro", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Atraso de 1 a 90"

    abrir_aba customers_path(busca: "Maria")
    assert_selector ".lista .datagrid-row", text: "PF", wait: 10
    abrir_ficha(@contract.customers.first, aba: "historico")
    na_aba_interna { assert_selector "h2", text: "Histórico do enquadramento financeiro" }
  end

  test "a conferência do impacto de um segmento usado ocupa a aba do editor, e Voltar e editar volta a ele" do
    tier = Tier.where(tenant: @alfa).where.not(segment_id: nil).first
    abrir_aba edit_settings_segment_path(tier.segment)
    assert_selector ".aba-raiz h1", text: "Editar segmento", wait: 10
    assert_button "Conferir o impacto", disabled: false
    fill_in "Texto do segmento", with: "contratos\n  tipo = PJ"
    # Clicar logo depois de digitar: a caixa perde o foco, e o cálculo à vista não pode desabilitar o botão no meio do clique.
    click_button "Conferir o impacto"
    assert_selector ".aba-raiz h1", text: "Conferir o impacto", wait: 10
    assert_selector ".tabs-selected .tabs-title", text: "Conferir o impacto"
    click_link "Voltar e editar"
    assert_selector ".aba-raiz h1", text: "Editar segmento", wait: 10
  end

  test "o glossário abre numa janela, e as seções rolam dentro dela sem tocar no endereço" do
    abrir_aba settings_segments_path
    assert_selector ".aba-raiz h1", text: "Segmentos", wait: 10
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Ver o glossário").click
    assert_selector ".janela-corpo", text: "Cada termo da linguagem dos segmentos", wait: 10
    endereco = page.evaluate_script("location.hash")
    within(".janela-corpo") { first("a[href^='#secao-']").click }
    assert_equal endereco, page.evaluate_script("location.hash")
  end

  test "a aba Índices se refaz sozinha pelo WebSocket quando a busca termina" do
    abrir_aba settings_indexes_path
    assert_selector ".aba-raiz h1", text: "Índices do Banco Central", wait: 10
    assert_selector "td", text: /Corrigido\s+1,52%/
    find(".aba-raiz .botao", text: "Editar índice", match: :first).click
    no_dialogo { assert_text "Motivo" }
    send_keys :escape
    assert_no_selector ".dialogo-conteudo"
    sem_rolagem_horizontal

    assert_selector "section[aria-labelledby=situacao] tr.datagrid-row", count: 1
    fake_bank(433 => [ [ @month.strftime("%d/%m/%Y"), "0.40" ] ])
    Indexes::Fetch.new.call
    sleep 1.6 # a aba que acabou de se refazer ignora avisos por 1,5 s (`spa/abas`, avisarMudanca)
    simular_evento({ channel: "IndexesChannel" }, { event: "indexes-changed" })
    assert_selector "section[aria-labelledby=situacao] tr.datagrid-row", count: 2, wait: 10
  end
end
