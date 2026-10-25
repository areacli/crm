require "application_system_test_case"

# Telas das contas de pagamento no navegador (12): lista, escolha, formulário do manifesto, edição com certificado e histórico, todas no axe.
class PaymentAccountsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @account = make_account(@alfa, modality: "pix", nickname: "Pix Alfa", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br", "expire_days" => 5 })
    @account.assign_values(secrets: { "certificate_password" => "abc123" }, files: { "certificate" => p12_upload(subject: "CN=Escola Alfa", days: 200, password: "abc123") })
    @account.save!
    make_account(@alfa, modality: "boleto", nickname: "Boleto Alfa", environment: "production", config: { "connection_result" => "refused" })
    Payments::AccountTester.new.call(PaymentAccount.find_by!(nickname: "Boleto Alfa"))
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "lista, escolha, cadastro e edição passam no axe e não rolam na horizontal" do
    visit settings_payment_accounts_path
    assert_selector "h1", text: "Contas de pagamento"
    assert_text "Pix Alfa"
    assert_text "Falhou"
    assert_acessivel
    assert_no_horizontal_scroll

    click_link "Nova conta"
    assert_selector "h1", text: "Nova conta de pagamento"
    assert_acessivel
    select "Pix", from: "Modalidade"
    select "Efí", from: "Fornecedor"
    click_button "Continuar"
    assert_selector "h2", text: "Dados da conta: Pix em Efí"
    assert_field "Certificado (.p12)", type: "file"
    assert_field "Client Secret", type: "password"
    assert_acessivel
    assert_no_horizontal_scroll

    visit edit_settings_payment_account_path(@account)
    assert_selector "h1", text: "Conta Pix Alfa"
    assert_text "CN=Escola Alfa"
    assert_text "Impressão digital (SHA-256)"
    assert_acessivel
    assert_no_horizontal_scroll

    click_button "Testar conexão"
    assert_text "Conexão com o fornecedor conferida"
    assert_text "Testar conexão"
    click_button "Gerar o segredo"
    within("dialog[open]") { click_button "Gerar segredo" }
    assert_text "Copie o segredo agora"
    assert_acessivel
    assert_selector "section[aria-labelledby=historico] td", text: "Segredo do webhook gerado"
  end

  def assert_no_horizontal_scroll
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end
end
