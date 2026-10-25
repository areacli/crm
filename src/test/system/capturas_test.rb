require "application_system_test_case"

# Fotos do README (regra do Paulo, 24/10/2026): a cada incremento, recriar as capturas do estado atual da aplicação.
# Só roda com CAPTURAS=1; grava em tmp/capturas/<nome>.png (o script deploy/rails/capturas.sh as move para docs/telas).
# Um incremento novo acrescenta aqui as suas telas, no fim de `TELAS`.
class CapturasTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    skip "defina CAPTURAS=1 para recriar as fotos do README" unless ENV["CAPTURAS"] == "1"
    FileUtils.mkdir_p(Rails.root.join("tmp/capturas"))
    page.driver.resize(1440, 900)
    @tenant = tenants(:alfa)
    # Carteira fictícia pequena e variada, com a data de hoje como referência.
    contract = Contract.create!(tenant: @tenant, code: "CT-0001")
    12.times do |index|
      customer = Customer.create!(tenant: @tenant, document: FakeData.cpf(index + 10), name: FakeData.name(index + 10), phone: "(11) 98888-00#{index.to_s.rjust(2, '0')}",
                                  email: "cliente#{index}@exemplo.com.br")
      2.times do |bill|
        Bill.create!(tenant: @tenant, contract: contract, customer: customer, number: "NF-#{index}/#{bill + 1}", due_date: Date.current - (index * 23 + bill * 9) + 40,
                     amount_cents: 15_000 + index * 4_700 + bill * 2_300)
      end
    end
    # Incremento 3: canais, pagamentos aplicados (quitado, parcial, excedente em crédito e pendente) e uma conferência de pagamentos.
    @channel = make_channel(@tenant, code: "341-1234-56789")
    @channel.update!(description: "Itaú, conta principal")
    make_channel(@tenant, code: "1029384756").update!(kind: :card, description: "Cielo, loja virtual")
    @channel.regenerate_webhook_secret!
    @paid_customer = Customer.order(:id).first
    @paid_customer.bills.order(:id).each_with_index do |bill, index|
      lines = [ payment_line("identificador" => "PIX-#{index}", "documento" => @paid_customer.document, "titulo" => bill.number,
                             "valor" => Money.format(index.zero? ? bill.amount_cents + 5_000 : bill.amount_cents / 3)) ]
      run_payments_import(lines, confirm: true)
    end
    run_payments_import([ payment_line("identificador" => "PIX-PEND", "titulo" => "NF-9999", "valor" => "300,00") ], confirm: true)
    @payments_import = Import.create!(tenant: @tenant, user: users(:joana), kind: :payments, mode: :incremental, status: :confirmed, original_name: "pagamentos-outubro.csv",
                                      size_bytes: 30_720, progress_percent: 100, checked_at: Time.current,
                                      summary: { lines: 310, valid: 298, rejected: 3, ignored: 9, amount_formatted: "98.400,00",
                                                 effect: { settled: 270, partial: 12, credits: 9, credit_cents: 310_000, pending_new: 6, pending_cents: 180_000,
                                                           applied_cents: 9_530_000 } })
    @payments_import.rejections.create!(line: 12, reason: "canal não cadastrado ou desativado")
    @payments_import.rejections.create!(line: 31, reason: "título não informado")
    @payments_import.rejections.create!(line: 45, reason: "pagamento já registrado, ignorado", ignored: true)
    # Incremento 4: acionamentos de três operadores nos últimos dias, em dois clientes.
    @contacted_customer = Customer.order(:id).second
    @contacted_customer.update!(phone: "(11) 98888-0001")
    [ [ :call_back, 1, "phone", "Pediu para ligar na sexta, depois das 14h.", 2.days.from_now ], [ :negotiating, 3, "whatsapp", "Quer parcelar em três vezes.\nEnviei a simulação.", nil ],
      [ :no_answer, 26, "phone", nil, nil ], [ :voicemail, 50, "phone", nil, nil ], [ :says_paid, 70, "email", "Informou pagamento no dia 10; conferir.", nil ] ].each_with_index do |(key, hours, channel, text, back), index|
      operator = [ users(:joana), users(:carlos), users(:ana) ][index % 3]
      customer = index.even? ? @contacted_customer : Customer.order(:id).third
      record_attempt(customer, operator, result: result_of(@tenant, key), channel: channel, text: text, contacted_at: (Time.current - hours.hours).strftime("%Y-%m-%dT%H:%M"),
                     return_at: back&.strftime("%Y-%m-%dT%H:%M"), contact_used: (channel == "phone" ? "(11) 98888-0001" : nil))
    end
    # Incremento 5: o credor reduz o valor de um título com pagamento parcial (política seguir: passa a pago, com excedente) e a divergência fica aberta.
    reduced = @paid_customer.bills.order(:id).second
    run_portfolio_import([ csv_line("documento" => @paid_customer.document, "nome" => @paid_customer.name, "contrato" => "CT-0001", "titulo" => reduced.number,
                                    "vencimento" => reduced.due_date.strftime("%d/%m/%Y"), "valor" => Money.format(reduced.paid_cents - 1_500)) ], confirm: true)
    @discrepancy = ValueDiscrepancy.order(:id).last
    @reduced_bill = reduced
    Import.create!(tenant: @tenant, user: users(:joana), mode: :full_sync, status: :checked, original_name: "carteira-outubro.csv", size_bytes: 40_960,
                   progress_percent: 100, checked_at: Time.current,
                   summary: { lines: 24, valid: 24, rejected: 0, customers: 12, customers_new: 0, amount_formatted: "6.200,00", bills_new: 4, bills_updated: 3,
                              bills_unchanged: 17, to_withdraw: { count: 2, amount_cents: 31_000 }, discrepancy_policy: "follow",
                              discrepancies: { count: 2, items: [
                                { number: "NF-1024/3", customer: "Maria da Silva", previous_cents: 100_000, reported_cents: 30_000, allocated_cents: 40_000, balance_before_cents: 60_000,
                                  balance_after_cents: 0, excess_cents: 10_000, effect: "becomes_paid" },
                                { number: "NF-2001", customer: "João Pereira", previous_cents: 50_000, reported_cents: 52_000, allocated_cents: 50_000, balance_before_cents: 0,
                                  balance_after_cents: 0, excess_cents: 0, effect: "record_only" } ] },
                              reported_surcharges: { lines: 3, penalty_cents: 6_000, interest_cents: 1_240, correction_cents: 310, other_cents: 0 } })
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  # nome do arquivo => caminho (lambda para os que dependem de registros criados no setup)
  TELAS = {
    "resumo" => -> { root_path },
    "clientes" => -> { customers_path },
    "ficha-do-cliente" => -> { customer_path(Customer.order(:id).first) },
    "conferencia-da-carteira" => -> { import_path(Import.order(:id).last) },
    "importacoes" => -> { imports_path },
    "importar-carteira" => -> { new_import_path },
    "configuracao" => -> { settings_portfolio_path },
    "usuarios" => -> { memberships_path },
    "perfis" => -> { profiles_path },
    "importar-pagamentos" => -> { new_import_path(kind: "payments") },
    # Só uma importação por credor pode esperar confirmação: a da carteira já foi fotografada, então sai de cena.
    "conferencia-de-pagamentos" => -> { Import.where(kind: "portfolio").update_all(status: "discarded"); @payments_import.update!(status: :checked); import_path(@payments_import) },
    "canais-de-recebimento" => -> { settings_channels_path },
    "canal-de-recebimento" => -> { edit_settings_channel_path(@channel) },
    "politicas-de-pagamento" => -> { settings_payment_policy_path },
    "ficha-com-pagos-e-credito" => -> { customer_path(@paid_customer) },
    # Incremento 4: acionamentos.
    "ficha-com-acionamentos" => -> { customer_path(@contacted_customer) },
    "acionamentos" => -> { contact_attempts_path },
    "resultados-de-acionamento" => -> { settings_contact_results_path },
    # Incremento 5: carteira revista.
    "divergencias-de-valor" => -> { value_discrepancies_path },
    "divergencia-de-valor" => -> { value_discrepancy_path(@discrepancy) },
    "historico-do-titulo" => -> { bill_path(@reduced_bill) }
  }.freeze

  # Telas longas, fotografadas com a janela mais alta para mostrar o que importa (o histórico, o formulário).
  ALTAS = %w[ficha-com-acionamentos].freeze

  test "recria as fotos do README" do
    TELAS.each do |nome, caminho|
      page.driver.resize(1440, ALTAS.include?(nome) ? 1700 : 900)
      visit instance_exec(&caminho)
      assert_selector "h1"
      page.save_screenshot(Rails.root.join("tmp/capturas/#{nome}.png").to_s)
    end
  end
end
