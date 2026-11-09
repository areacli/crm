require "application_system_test_case"

# Telas de pagamentos no navegador, nas abas da casca: métodos de recebimento, políticas, importações de pagamentos e estornos, ficha com crédito e resumo.
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
    entrar_na_casca
  end

  test "o resumo, canais, políticas, importações e ficha abrem nas abas" do
    assert_selector ".aba-raiz", text: "Recuperado em", wait: 15

    # Métodos de recebimento e políticas estão na SPA (fase 7), fora do axe (D7).
    visit settings_channels_path
    assert_selector ".aba-raiz h1", text: "Métodos de recebimento", wait: 15
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar método de recebimento").click
    no_dialogo { assert_field "Código" }
    send_keys :escape
    abrir_aba settings_payment_policy_path
    assert_selector ".aba-raiz h1", text: "Políticas de pagamento", wait: 10
    abrir_aba edit_settings_channel_path(@channel)
    assert_selector ".aba-raiz h2", text: "Webhook de pagamento", wait: 10
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Gerar novo segredo").click
    no_dialogo { assert_text "O segredo atual, se houver, deixa de valer na hora" }
    send_keys :escape

    # Importações estão na SPA (fase 5), fora do axe (D7).
    visit new_import_path(tipo: "pagamentos")
    assert_selector ".aba-raiz h1", text: "Importar pagamentos", wait: 15
    assert_selector ".aba-raiz .filebox"
    visit import_path(@checked)
    assert_selector ".aba-raiz", text: "Pagamentos válidos", wait: 15
    assert_text "título não informado"

    # A ficha está na SPA (fase 3): a aba Pagamentos, com as grades e o diálogo de transferir.
    visitar_ficha(@customer, aba: "pagamentos")
    na_aba_interna do
      assert_selector "h2", text: "Pagos"
      assert_selector "h2", text: "Crédito por contrato"
      click_link "Transferir crédito"
    end
    assert_selector ".window .panel-title", text: "Transferir crédito"
  end

  test "transferir crédito pelo diálogo da ficha" do
    visitar_ficha(@customer, aba: "pagamentos")
    na_aba_interna { click_link "Transferir crédito" }
    no_dialogo do
      fill_in "Código do contrato de destino", with: "CT-2"
      fill_in "Valor", with: "20,00"
      fill_in "Motivo", with: "migração de contrato"
    end
    gravar_dialogo "Transferir"
    assert_aviso "transferidos para o contrato CT-2"
    assert_equal 3_000, Contract.find_by!(code: "CT-1").credit_cents
    assert_equal 2_000, Contract.find_by!(code: "CT-2").credit_cents
  end
end
