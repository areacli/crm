require "application_system_test_case"

# Encargos e valor atualizado no navegador (09), nas abas da casca: ficha com a memória de cálculo na janela do título, lista, resumo, regras do item,
# conferência do impacto com o aviso do CDC e comparação dos acréscimos na carga, sem rolagem horizontal.
class ChargesSystemScreensTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    seed_indexes!
    configure_charges(@alfa)
    @bill = make_bill(@alfa, due: DUE)
    recalc(@alfa)
    recalc_values(@alfa)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def entrar
    entrar_na_casca
  end

  test "a ficha mostra o atualizado e abre a memória de cálculo sob pedido; lista e resumo nas abas" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      entrar
      assert_selector ".aba-raiz dt", text: "Atualizado", wait: 15
      sem_rolagem_horizontal

      # Clientes e a ficha estão na SPA (fase 3): a grade da lista e a janela do título.
      visit customers_path
      assert_selector ".lista .datagrid-header", text: "Atualizado"
      assert_selector ".lista .datagrid-row", text: "R$ 1.057,56"

      abrir_ficha(@bill.customer)
      na_aba_interna do
        assert_no_selector ".datagrid-row-expander"
        click_link "NF-1"
      end
      within(".janela-corpo") do
        assert_selector "dl.composicao dd", text: "R$ 1.005,34"
        assert_selector "caption, .legenda-da-grade", text: /Memória de cálculo do título NF-1/
        assert_selector ".datagrid-row, td", text: /IPCA/
      end
    end
  end

  # Na SPA (fase 7): as regras do item numa aba própria, e a conferência do impacto ocupa essa aba; o axe saiu da área interna (plano, D7).
  test "o enquadramento financeiro, as regras do Demais, a conferência do impacto em segundo plano e o aviso do CDC, nas abas" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      entrar
      visit settings_tiers_path # o endereço antigo leva à aba na casca
      assert_selector ".aba-raiz h1", text: "Enquadramento financeiro", wait: 15
      find(".aba-raiz .datagrid-header [aria-label='Mostrar os detalhes de todas as linhas']", match: :first).click
      assert_selector ".datagrid-row-detail p", text: "Encargos: multa 2% · juros 1% a.m. simples · IPCA · sem honorários."
      assert_selector ".aba-raiz h2", text: /\AEncargos do credor/
      sem_rolagem_horizontal

      menu_da_linha("Demais", "Editar regras")
      assert_selector ".aba-raiz h1", text: "Regras do item Demais", wait: 10
      assert_selector ".aba-raiz h2", text: "Encargos"
      sem_rolagem_horizontal

      fill_in "tier_fine_pct", with: "5"
      click_button "Conferir o impacto"
      assert_selector ".aba-raiz h1", text: "Conferir o impacto", wait: 10
      assert_text "Conferindo"
      perform_enqueued_jobs(only: TierReviewJob)
      simular_evento({ channel: "SegmentsChannel", tenant_id: tenants(:alfa).id }, { event: "tier-review-ready" })
      assert_selector "h2", text: "Valor atualizado", wait: 10
      assert_selector "td", text: "R$ 1.057,56"
      assert_text "Multa acima de 2% em Demais"
      sem_rolagem_horizontal
      click_button "Confirmar mudança"
      assert_aviso "Enquadramento financeiro de Escola Alfa atualizado"
      assert_selector ".aba-raiz h1", text: "Enquadramento financeiro", wait: 10
    end
  end

  test "a conferência de uma carga com acréscimos informados mostra a comparação com o calculado" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      header = CsvHelper::HEADER + %w[multa_credor]
      checked = run_portfolio_import([ csv_line("documento" => PaymentsHelper::JOAO, "nome" => "João", "contrato" => "CT-9", "titulo" => "NF-9", "vencimento" => "15/07/2026", "valor" => "1.000,00", "multa_credor" => "20,00") ], header: header)
      entrar
      visit import_path(checked) # na SPA desde a fase 5
      assert_selector ".aba-raiz h2", text: "Acréscimos informados e calculados pelo CRM", wait: 15
      sem_rolagem_horizontal
    end
  end
end
