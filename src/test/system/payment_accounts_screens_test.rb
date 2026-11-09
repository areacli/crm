require "application_system_test_case"

# Telas das contas de pagamento no navegador (12), nas abas da casca: lista, escolha, formulário do manifesto, edição com certificado e histórico.
class PaymentAccountsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @account = make_account(@alfa, modality: "pix", nickname: "Pix Alfa", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br", "expire_days" => 5 })
    @account.assign_values(secrets: { "certificate_password" => "abc123" }, files: { "certificate" => p12_upload(subject: "CN=Escola Alfa", days: 200, password: "abc123") })
    @account.save!
    make_account(@alfa, modality: "boleto", nickname: "Boleto Alfa", environment: "production", config: { "connection_result" => "refused" })
    Payments::AccountTester.new.call(PaymentAccount.find_by!(nickname: "Boleto Alfa"))
    entrar_na_casca
  end

  # Na SPA (fase 7): a nova integração num formulário só (a escolha traz os campos do fornecedor sem trocar de tela), a edição numa aba própria; o axe saiu da área
  # interna (plano, D7).
  test "lista, escolha, cadastro e edição nas abas, sem rolar na horizontal" do
    visit settings_channels_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Métodos de recebimento", wait: 15
    find(".aba-raiz .datagrid-header [aria-label='Mostrar os detalhes de todas as linhas']", match: :first).click
    assert_text "Pix Alfa"
    assert_text "Falhou"
    assert_no_horizontal_scroll

    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar integração").click
    assert_selector ".aba-raiz h1", text: "Nova integração", wait: 10
    assert_text "Escolha o meio de pagamento e o fornecedor"
    escolher "Meio de pagamento", "Pix"
    escolher "Fornecedor", "Efí"
    # O campo de arquivo vira o `filebox` do EasyUI, que esconde o campo real.
    assert_selector ".aba-raiz label", text: "Certificado (.p12)", wait: 10
    assert_selector "input[type=file][name='payment_account[files][certificate]']", visible: :all
    assert_field "Client Secret", type: "password"
    assert_no_horizontal_scroll

    abrir_aba edit_settings_payment_account_path(@account)
    assert_selector ".aba-raiz h1", text: "Integração Pix Alfa", wait: 10
    assert_text "CN=Escola Alfa"
    assert_text "Impressão digital (SHA-256)"
    assert_no_horizontal_scroll

    click_button "Testar conexão"
    assert_aviso "Conexão com o fornecedor conferida"
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Gerar novo segredo do webhook").click
    no_dialogo { click_button "Gerar novo segredo" }
    # O fim da ação leva à aba da integração, que já está aberta: ela se refaz e mostra o segredo uma vez.
    assert_selector ".aba-raiz", text: "Copie o segredo agora", wait: 10
    assert_selector "section[aria-labelledby=historico] td", text: "Segredo do webhook gerado"
  end

  def assert_no_horizontal_scroll
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end
end
