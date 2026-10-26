require "application_system_test_case"

# Telas de pagamentos no navegador: canais, políticas, importações de pagamentos e estornos, ficha com crédito e resumo, todas no axe.
class PaymentsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @channel.regenerate_webhook_secret!
    bill = make_bill(@alfa, amount_cents: 100_000)
    @customer = bill.customer
    make_bill(@alfa, number: "NF-2", amount_cents: 50_000, document: JOAO, contract_code: "CT-2", name: "João Pereira")
    run_payments_import([ payment_line("valor" => "1.050,00"), payment_line("identificador" => "P-PEND", "titulo" => "NF-404", "valor" => "30,00") ], confirm: true)
    @checked = Import.create!(tenant: @alfa, user: users(:joana), kind: :payments, mode: :incremental, status: :checked, original_name: "pagamentos.csv", size_bytes: 2048,
                              progress_percent: 100, checked_at: Time.current,
                              summary: { lines: 3, valid: 2, rejected: 1, ignored: 0, amount_formatted: "500,00",
                                         effect: { settled: 1, partial: 1, credits: 0, credit_cents: 0, pending_new: 0, applied_cents: 50_000 } })
    @checked.rejections.create!(line: 4, reason: "título não informado")
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "resumo, canais, políticas, importações e ficha passam no axe" do
    assert_text "Recuperado em"
    assert_acessivel

    visit settings_channels_path
    assert_selector "h1", text: "Canais de recebimento"
    assert_acessivel
    click_link "Políticas de pagamento"
    assert_selector "h1", text: "Políticas de pagamento"
    assert_acessivel
    click_link "Canais de recebimento"
    click_link "Novo canal"
    assert_selector "dialog#painel[open][data-variant=drawer]", text: "Novo canal de recebimento"
    assert_acessivel
    within("dialog#painel[open]") { click_button "Cancelar" }
    visit edit_settings_channel_path(@channel)
    assert_acessivel
    click_link "Trocar o segredo"
    assert_selector "dialog#painel[open]", text: "Gerar um novo segredo?"
    assert_acessivel
    within("dialog#painel[open]") { click_button "Cancelar" }

    visit new_import_path(kind: "payments")
    assert_selector "h1", text: "Importar pagamentos"
    assert_acessivel
    visit new_import_path(kind: "reversals")
    assert_selector "h1", text: "Importar estornos"
    assert_acessivel

    visit import_path(@checked)
    assert_text "Pagamentos válidos"
    assert_text "título não informado"
    assert_acessivel

    visit imports_path
    assert_acessivel

    visit customer_path(@customer, aba: "pagamentos")
    assert_selector "h2", text: "Pagos"
    assert_selector "h2", text: "Crédito por contrato"
    assert_acessivel
    click_link "Transferir crédito"
    assert_selector "dialog#painel[open]", text: "Transferir crédito"
    assert_acessivel
  end

  test "transferir crédito pela janela da ficha" do
    visit customer_path(@customer, aba: "pagamentos")
    click_link "Transferir crédito"
    within("dialog#painel[open]") do
      fill_in "Código do contrato de destino", with: "CT-2"
      fill_in "Valor", with: "20,00"
      fill_in "Motivo", with: "migração de contrato"
      click_button "Transferir", exact: true
    end
    assert_text "transferidos para o contrato CT-2"
    assert_equal 3_000, Contract.find_by!(code: "CT-1").credit_cents
    assert_equal 2_000, Contract.find_by!(code: "CT-2").credit_cents
  end
end
