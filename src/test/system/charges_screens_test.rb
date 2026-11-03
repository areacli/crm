require "application_system_test_case"

# Encargos e valor atualizado no navegador (09): ficha com a memória de cálculo aberta pelo htmx, lista, resumo, aba Segmentos e encargos, formulário
# com o grupo Encargos, conferência do impacto com o aviso do CDC e comparação dos acréscimos na carga; todos no axe, sem rolagem horizontal.
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
    entrar_pela_spa(users(:joana).email_address, "senha-de-teste-1")
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "a ficha mostra o atualizado e abre a memória de cálculo sob pedido; lista e resumo passam no axe" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      entrar
      assert_selector "dt", text: "Atualizado"
      assert_acessivel
      sem_rolagem_horizontal

      visit customers_path
      assert_selector "th", text: "Atualizado"
      assert_selector "td", text: "R$ 1.057,56"
      assert_acessivel

      visit customer_path(@bill.customer)
      assert_no_selector "section[aria-labelledby=titulos] button[data-alternar-detalhe]"
      click_link "NF-1"
      assert_selector "dl.composicao dd", text: "R$ 1.005,34"
      assert_selector "caption", text: /Memória de cálculo do título NF-1/
      assert_selector "#memoria-de-calculo ~ div td, section[aria-labelledby=memoria-de-calculo] td", text: /IPCA/
      assert_acessivel
      sem_rolagem_horizontal
    end
  end

  test "o enquadramento financeiro, as regras do Demais, a conferência do impacto em segundo plano e o aviso do CDC passam no axe" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      entrar
      visit settings_tiers_path
      assert_selector "h1", text: "Enquadramento financeiro"
      assert_selector "tr.detalhe-da-linha p", text: "Encargos: multa 2% · juros 1% a.m. simples · IPCA · sem honorários.", visible: :all
      assert_selector "legend", text: "Parâmetros de encargos do credor"
      assert_acessivel
      sem_rolagem_horizontal

      find("button.menu-de-linha[aria-label='Ações de Demais']").click
      click_link "Editar regras"
      assert_selector "legend", text: "Encargos"
      assert_acessivel
      sem_rolagem_horizontal

      fill_in "tier_fine_pct", with: "5"
      click_button "Conferir o impacto"
      assert_selector "h1", text: "Conferir o impacto"
      assert_text "Conferindo"
      perform_enqueued_jobs(only: TierReviewJob)
      assert_selector "h2", text: "Valor atualizado", wait: 10
      assert_selector "td", text: "R$ 1.057,56"
      assert_text "Multa acima de 2% em Demais"
      assert_acessivel
      sem_rolagem_horizontal
      click_button "Confirmar mudança"
      assert_text "Enquadramento financeiro de Escola Alfa atualizado"
    end
  end

  test "a conferência de uma carga com acréscimos informados mostra a comparação com o calculado e passa no axe" do
    travel_to(TODAY.in_time_zone.change(hour: 10)) do
      header = CsvHelper::HEADER + %w[multa_credor]
      checked = run_portfolio_import([ csv_line("documento" => PaymentsHelper::JOAO, "nome" => "João", "contrato" => "CT-9", "titulo" => "NF-9", "vencimento" => "15/07/2026", "valor" => "1.000,00", "multa_credor" => "20,00") ], header: header)
      entrar
      visit import_path(checked)
      assert_selector "h2", text: "Acréscimos informados e calculados pelo CRM"
      assert_acessivel
      sem_rolagem_horizontal
    end
  end
end
