require "application_system_test_case"

# Redesenho denso e corporativo, fase 2 (decisão 0022): as telas que a fase 1 deixou no padrão antigo passam no axe, nenhuma rola na horizontal a 1440, 1024 e 390 px, e as
# ações restantes abrem no painel compartilhado (confirmação, modal e painel lateral) sem `<details>` nem formulário aberto na página.
class Phase2ScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  LARGURAS = [ 1440, 1024, 390 ].freeze

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_back
    @import = Import.create!(tenant: @alfa, user: users(:joana), kind: :portfolio, mode: :incremental, status: :checked, original_name: "carteira.csv", size_bytes: 20_480, progress_percent: 100,
                             checked_at: Time.current, summary: { lines: 10, valid: 10, rejected: 0, customers: 3, customers_new: 1, amount_formatted: "1.000,00", bills_new: 2, bills_updated: 1, bills_unchanged: 7 })
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal(rota) = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"), "#{rota} rola na horizontal a #{page.evaluate_script('window.innerWidth')} px")

  def rotas
    [ contact_attempts_path, imports_path, new_import_path, new_import_path(kind: "payments"), new_import_path(kind: "reversals"), import_path(@import), value_discrepancies_path, agreements_path,
      agreement_path(@agreement), pending_agreements_path, pending_promises_path, reversal_waits_path, agreement_exports_path, memberships_path, membership_path(Membership.find_by!(user: users(:carlos))),
      profiles_path, data_retention_path, settings_tenant_registry_path, settings_portfolio_path, settings_channels_path, edit_settings_channel_path(@alfa.payment_channels.first || make_channel(@alfa)),
      settings_payment_policy_path, settings_payment_accounts_path, new_settings_payment_account_path(tenant_id: @alfa.id), settings_segments_path, settings_promises_path, settings_indexes_path,
      settings_contact_results_path, new_customer_agreement_simulation_path(@customer), agreement_path(@agreement), bill_path(@nf1) ]
  end

  test "as telas da fase 2 passam no axe e não rolam na horizontal a 1440, 1024 e 390 px" do
    LARGURAS.each do |largura|
      page.driver.resize(largura, 900)
      rotas.each do |rota|
        visit rota
        assert_selector "h1", wait: 10
        sem_rolagem_horizontal(rota)
        assert_acessivel if largura == 1440
      end
    end
  end

  test "a confirmação, o modal e o painel lateral abrem pelo mecanismo único e passam no axe" do
    page.driver.resize(1440, 900)
    visit imports_path
    assert_selector "html[data-cable='conectado']" # a lista se refaz quando o WebSocket conecta e fecharia o menu aberto
    assert_selector "tbody tr button.menu-de-linha", wait: 10
    find("tbody tr button.menu-de-linha", match: :first).click
    click_link "Descartar importação"
    assert_selector "dialog#painel[open][data-variant=modal]", text: "Descartar a importação?"
    assert_acessivel
    within("dialog#painel[open]") { click_button "Cancelar" }
    assert_no_selector "dialog#painel[open]"

    visit memberships_path
    click_link "Novo usuário"
    assert_selector "dialog#painel[open][data-variant=drawer]", text: "Novo usuário"
    assert_acessivel
    fill_in "E-mail", with: "novo@exemplo.com.br"
    within("dialog#painel[open]") { click_button "Salvar" }
    assert_selector "dialog#painel[open] [role=alert], dialog#painel[open] .aviso", text: /nome|Nome/, wait: 10 # 422 dentro do painel
    assert_acessivel

    visit agreement_path(@agreement)
    find("button.menu-de-linha[aria-label='Mais ações do acordo']").click
    click_link "Quebrar o acordo"
    assert_selector "dialog#painel[open][data-variant=modal]", text: "Quebrar o acordo"
    fill_in "Motivo da quebra", with: "teste da recusa dentro do painel"
    within("dialog#painel[open]") { click_button "Quebrar o acordo" }
    assert_selector "dialog#painel[open] .aviso[data-tone=danger]", wait: 10 # o acordo não está em atraso: a regra recusa e o formulário volta com a mensagem
    assert_acessivel
  end

  test "nenhuma lista ou ficha tem formulário de dados aberto nem <details> com formulário" do
    [ imports_path, memberships_path, profiles_path, agreement_path(@agreement), reversal_waits_path, pending_promises_path, data_retention_path, settings_indexes_path ].each do |rota|
      visit rota
      assert_selector "h1"
      assert_no_selector "main details form, main details input, main details select, main details textarea", visible: :all, wait: 0
    end
  end
end
