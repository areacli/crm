require "application_system_test_case"

# A página pública de pagamento no navegador (12, parte C): axe, celular sem rolagem lateral, o cartão pelo módulo do fornecedor falso sob a política de
# segurança de conteúdo da página, clique duplo, recusa e a área que se refaz quando o estado muda. Nenhum dado de cartão chega ao servidor.
class CheckoutsScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @checkout = make_checkout(customer: @customer, boleto: true, pix: true)
  end

  def assert_no_horizontal_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "rolagem horizontal em #{page.current_path}"
  end

  def fill_card(number: "4000000000000004")
    fill_in "Número do cartão", with: number
    fill_in "Nome impresso no cartão", with: "MARIA SOUZA"
    fill_in "Validade (mês/ano)", with: "12/30"
    fill_in "Código de segurança", with: "123"
  end

  def watch_policy_violations = page.execute_script("window.__violations = []; document.addEventListener('securitypolicyviolation', (e) => window.__violations.push(e.violatedDirective + ' ' + e.blockedURI))")

  test "a página passa no axe e não rola na horizontal, no computador e no celular" do
    visit checkout_path(@checkout)
    assert_selector "h1", text: "Pagamento"
    assert_acessivel
    assert_no_horizontal_scroll
    page.driver.resize(375, 800)
    visit checkout_path(@checkout)
    assert_selector "h1", text: "Pagamento"
    assert_acessivel
    assert_no_horizontal_scroll
  ensure
    page.driver.resize(1440, 900)
  end

  test "o QR Code do Pix carrega daqui e o PDF do boleto abre daqui" do
    visit checkout_path(@checkout)
    assert_selector "img[alt^='QR Code do Pix']"
    assert_equal true, page.evaluate_script("document.querySelector(\"img[alt^='QR Code do Pix']\").naturalWidth > 0")
    assert_link "Abrir o boleto (PDF)", href: checkout_boleto_path(@checkout)
  end

  test "o cartão é aprovado pelo módulo do fornecedor, sem violação da política de conteúdo, e o servidor só vê o token e as parcelas" do
    visit checkout_path(@checkout)
    watch_policy_violations
    fill_card
    assert_selector "form[data-cartao][data-bandeira]" # a bandeira troca a lista de parcelas; só depois se escolhe
    select "3x de R$ 333,00", from: "Parcelas"
    click_button "Pagar R$ 999,00"
    assert_text "Pagamento no cartão aprovado"
    assert_no_selector "form[data-cartao]"
    assert_equal [], page.evaluate_script("window.__violations")
    attempt = PaymentInstrument.where(kind: "card").sole
    assert_equal 3, attempt.response_summary["installments"]
    assert_acessivel
    assert_not_includes File.read(Rails.root.join("log/test.log")).last(300_000), "4000000000000004"
  end

  test "recusa por segurança: mensagem em pt-BR, formulário limpo e outro cartão aprova" do
    visit checkout_path(@checkout)
    fill_card(number: "4000000000000002")
    click_button "Pagar R$ 999,00"
    assert_text "não autorizou o pagamento por segurança"
    assert_field "Número do cartão", with: ""
    assert_field "Código de segurança", with: ""
    assert_acessivel
    fill_card
    click_button "Pagar R$ 999,00"
    assert_text "Pagamento no cartão aprovado"
    assert_equal 2, PaymentInstrument.where(kind: "card").count
  end

  test "clique duplo no botão cobra uma vez só" do
    visit checkout_path(@checkout)
    fill_card
    page.execute_script("const b = document.querySelector('form[data-cartao] button[type=submit]'); b.click(); b.click()")
    assert_text "Pagamento no cartão aprovado"
    assert_equal 1, PaymentInstrument.where(kind: "card").count
  end

  test "quando o estado muda (o canal avisa), a área de pagamento se refaz sozinha" do
    visit checkout_path(@checkout)
    assert_selector "form[data-cartao]"
    @checkout.instruments.find_by(kind: "pix").update!(state: "paid")
    Payments::Checkouts.sync(@checkout)
    page.execute_script("document.body.dispatchEvent(new CustomEvent('cable:checkout-changed'))")
    assert_text "Pagamento confirmado. Obrigado."
    assert_no_selector "form[data-cartao]"
    assert_acessivel
  end

  test "link inexistente mostra a página de indisponível, acessível e sem rolagem" do
    visit "/pagar/nao-existe"
    assert_selector "h1", text: "Este link de pagamento não está disponível"
    assert_acessivel
    assert_no_horizontal_scroll
  end

  test "com a Efí: a biblioteca fixada carrega pelo importmap sob a política de conteúdo, reconhece a bandeira no navegador e as parcelas vêm do adaptador" do
    beta = tenants(:beta)
    customer = make_customer(beta, document: PaymentsHelper::JOAO, name: "João Pereira")
    make_efi_account(beta, modality: "card", environment: "production")
    installments = [ { "installment" => 1, "has_interest" => false, "value" => 5_000, "currency" => "50,00", "interest_percentage" => 0 },
                     { "installment" => 2, "has_interest" => true, "value" => 2_600, "currency" => "26,00", "interest_percentage" => 400 } ]
    use_efi_client(efi_client.on(:get, "/v1/installments", body: { "code" => 200, "data" => { "rate" => 0, "name" => "visa", "installments" => installments } }))
    checkout = Payments::Checkouts.create(tenant: beta, customer: customer, amount_cents: 5_000, card: true)
    visit checkout_path(checkout)
    watch_policy_violations
    fill_in "Número do cartão", with: "4111 1111 1111 1111"
    assert_selector "#cartao-parcelas option", text: "2x de R$ 26,00 (total R$ 52,00)", wait: 10
    assert_equal [], page.evaluate_script("window.__violations.filter((v) => !v.includes('tokenizer') && !v.includes('clearsale') && !v.includes('fpcs-monitor'))")
    assert_equal "visa", page.evaluate_script("document.querySelector('form[data-cartao]').dataset.bandeira")
  end
end
