require "application_system_test_case"

# Redesenho denso e corporativo, fase 2 (decisão 0022), agora na SPA (fase 7 do port): as telas da administração e da configuração abrem nas abas sem rolar na
# horizontal, e as ações abrem nos diálogos presos à aba (confirmação, modal e painel lateral), sem `<details>` nem formulário aberto na página.
class Phase2ScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  LARGURAS = [ 1440, 1024, 390 ].freeze

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_back
    # O cenário do acordo tem data fixa (30/10/2026) e a tela roda no relógio de verdade: os vencimentos vão para a frente, para o acordo não estar em
    # atraso no dia em que o teste roda (a recusa da quebra, abaixo, depende disso).
    @agreement.titles.update_all(due_date: Date.current + 30)
    @import = Import.create!(tenant: @alfa, user: users(:joana), kind: :portfolio, mode: :incremental, status: :checked, original_name: "carteira.csv", size_bytes: 20_480, progress_percent: 100,
                             checked_at: Time.current, summary: { lines: 10, valid: 10, rejected: 0, customers: 3, customers_new: 1, amount_formatted: "1.000,00", bills_new: 2, bills_updated: 1, bills_unchanged: 7 })
    entrar_na_casca
  end

  def sem_rolagem_horizontal(rota) = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"), "#{rota} rola na horizontal a #{page.evaluate_script('window.innerWidth')} px")

  # As telas da administração e da configuração, que foram para a SPA na fase 7 (as das fases 3 a 6 já tinham saído); lá o axe não roda (D7).
  def rotas
    [ memberships_path, membership_path(Membership.find_by!(user: users(:carlos))),
      profiles_path, new_profile_path, data_retention_path, settings_tenant_registry_path, settings_portfolio_path, settings_channels_path,
      edit_settings_channel_path(@alfa.payment_channels.first || make_channel(@alfa)), settings_payment_policy_path, new_settings_payment_account_path(credor: @alfa.id),
      settings_segments_path, new_settings_segment_path(credor: @alfa.id), settings_tiers_path, settings_promises_path, settings_indexes_path, settings_contact_results_path ]
  end

  test "as telas da administração e da configuração abrem nas abas e não rolam na horizontal a 1440 e 1024 px" do
    visit root_path
    assert_selector "#abas .tabs-title", wait: 15
    [ 1440, 1024 ].each do |largura|
      page.driver.resize(largura, 900)
      rotas.each do |rota|
        abrir_aba rota
        assert_selector ".aba-raiz h1", wait: 10
        esperar_os_pedidos
        sem_rolagem_horizontal(rota)
        find(".tabs-selected .tabs-close").click
      end
    end
  end

  test "a confirmação, o modal e o painel lateral abrem pelo mecanismo único, nos diálogos presos à aba" do
    page.driver.resize(1440, 900)
    # Importações estão na SPA (fase 5): a confirmação curta pelo menu da linha, num diálogo preso à aba.
    visit imports_path
    assert_selector ".aba-raiz #importacoes .datagrid-row .menu-de-linha", wait: 15
    first(".aba-raiz #importacoes .datagrid-row .menu-de-linha").click
    find("[popover]:popover-open .botao", text: "Descartar importação").click
    assert_selector ".window .panel-title", text: "Descartar a importação?"
    no_dialogo { click_button "Cancelar" }
    assert_no_selector ".dialogo-conteudo"

    # Usuários estão na SPA (fase 7): a recusa (422) volta dentro do diálogo preso à aba.
    visit memberships_path
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar usuário", wait: 15).click
    no_dialogo { fill_in "E-mail", with: "novo@exemplo.com.br" }
    gravar_dialogo "Salvar", erro: true
    assert_selector ".dialogo-conteudo .aviso", text: /nome|Nome/
    send_keys :escape

    # A página do acordo está na SPA (fase 4): a recusa da regra volta dentro do diálogo preso à aba.
    visit agreement_path(@agreement)
    assert_selector ".aba-raiz h1", text: /Acordo/, wait: 15
    mais_acoes "Quebrar o acordo"
    no_dialogo { fill_in "Motivo da quebra", with: "teste da recusa dentro do diálogo" }
    gravar_dialogo "Quebrar o acordo", erro: true
    assert_selector ".dialogo-conteudo .aviso[data-tone=danger]" # o acordo não está em atraso: a regra recusa e o formulário volta com a mensagem
  end

  test "nenhuma lista ou ficha tem formulário de dados aberto nem <details> com formulário" do
    [ imports_path, memberships_path, profiles_path, reversal_waits_path, data_retention_path, settings_indexes_path ].each do |rota|
      visit rota
      assert_selector "h1"
      assert_no_selector "main details form, main details input, main details select, main details textarea", visible: :all, wait: 0
    end
  end
end
