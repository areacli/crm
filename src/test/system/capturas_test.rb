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
      customer = Customer.create!(tenant: @tenant, document: FakeData.cpf(index + 10), name: FakeData.name(index + 10))
      add_contact(customer, "phone", "(11) 98888-00#{index.to_s.rjust(2, '0')}")
      add_contact(customer, "email", "cliente#{index}@exemplo.com.br")
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
    @contacted_customer.contacts.find_or_create_by!(tenant_id: @tenant.id, kind: "phone", key: "11988880001") { |c| c.value = "(11) 98888-0001"; c.origin = "load" }
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
    # Incremento 6: cadastro do credor, contatos do cliente (carga, tela e acionamento, em várias situações) e avisos da conferência.
    Registry::TenantEditor.new(users(:joana)).update(@tenant, cnpj: "11.222.333/0001-81", legal_name: "Escola Alfa Educação Ltda", trade_name: "Escola Alfa", street: "Rua das Palmeiras",
                                                     number: "450", district: "Centro", city: "Campinas", state: "SP", zip: "13010-000", email: "contato@escolaalfa.com.br", phone: "(19) 3000-1000")
    editor = Registry::ContactEditor.new(users(:joana))
    add_contact(@contacted_customer, "phone", "(11) 91111-2222", origin: "load", seen_in_import_at: 2.days.ago)
    add_contact(@contacted_customer, "email", "cliente@exemplo.com.br", origin: "load", seen_in_import_at: 2.days.ago)
    add_address(@contacted_customer, { street: "Rua das Flores", number: "120", complement: "ap 3", district: "Centro", city: "São Paulo", state: "SP", zip: "01001-000" }, origin: "load")
    wrong = add_contact(@contacted_customer, "phone", "(11) 93333-4444", origin: "contact_attempt")
    editor.mark_invalid(wrong, "número de outra pessoa")
    editor.do_not_disturb(@contacted_customer.contacts.find_by!(key: "11988880001"), 3.days.ago.to_date.iso8601, "pediu para não ligar no trabalho")
    editor.add(@contacted_customer, kind: "phone", fields: { value: "(11) 4444-5555" })
    editor.rename(@contacted_customer, "#{@contacted_customer.name} Souza")
    @conference = Import.where(kind: "portfolio", status: "checked").order(:id).last
    @conference.update!(summary: @conference.summary.merge("contact_warnings" => 3, "correction_policy" => "screen", "contacts" => 41,
                                                          "kept_by_tenant" => { "names" => { "count" => 1, "items" => [ { "current_name" => @contacted_customer.name, "load_name" => @contacted_customer.name.delete_suffix(" Souza") } ] },
                                                                                "contacts" => { "count" => 1, "items" => [ { "customer" => @contacted_customer.name, "kind" => "phone", "value" => "(11) 98888-0001", "status" => "do_not_disturb" } ] } }))
    @conference.warnings.create!(line: 12, reason: "endereço ignorado (CEP inválido)")
    @conference.warnings.create!(line: 31, reason: "telefone2 ignorado (menos de 8 dígitos)")
    @conference.warnings.create!(line: 44, reason: "telefone igual ao do credor (entra inválido)")
    # Incremento 7: guarda de dados (dois previstos, um retido, um já anonimizado, execuções) e a exportação dos dados de um cliente.
    @tenant.setting.update!(retention_years: 5)
    @forecast_customer = make_full_customer(@tenant, ended_on: Date.current - 5.years + 12.days, document: FakeData.cpf(300), name: FakeData.name(300), code: "CT-P1")
    make_full_customer(@tenant, ended_on: Date.current - 5.years + 25.days, document: FakeData.cpf(301), name: FakeData.name(301), code: "CT-P2")
    retained = make_full_customer(@tenant, ended_on: Date.current - 6.years, document: FakeData.cpf(302), name: FakeData.name(302), code: "CT-P3")
    Titular::Retainer.new(users(:joana)).retain(retained, "Ação judicial nº 0001234-56.2025 em curso (art. 16 da LGPD)")
    @anonymized_customer = make_full_customer(@tenant, ended_on: Date.current - 7.years, document: FakeData.cpf(303), name: FakeData.name(303), code: "CT-P4")
    Titular::Anonymizer.in_batch(@tenant.id, [ @anonymized_customer.id ])
    TaskRun.create!(tenant: @tenant, name: "data_retention", status: "succeeded", started_at: Time.current.change(hour: 3), finished_at: Time.current.change(hour: 3, min: 1), processed: 4)
    TaskRun.create!(tenant: @tenant, name: "data_retention", status: "skipped", started_at: 1.day.ago.change(hour: 3), finished_at: 1.day.ago.change(hour: 3), note: "Há uma importação em andamento.")
    TaskRun.create!(tenant: @tenant, name: "data_retention", status: "succeeded", started_at: 2.days.ago.change(hour: 3), finished_at: 2.days.ago.change(hour: 3, min: 1), processed: 0)
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
    "historico-do-titulo" => -> { bill_path(@reduced_bill) },
    # Incremento 6: cadastros.
    "ficha-com-contatos" => -> { customer_path(@contacted_customer) },
    "dados-do-credor" => -> { settings_tenant_registry_path },
    "politica-de-correcao" => -> { settings_portfolio_path },
    # Incremento 7: direitos do titular e guarda de dados.
    "guarda-de-dados" => -> { data_retention_path },
    "ficha-anonimizada" => -> { customer_path(@anonymized_customer) },
    "exportacao-de-dados" => -> { customer_data_export_path(@forecast_customer, token: Rails.application.message_verifier(:data_export).generate([ @forecast_customer.id, users(:joana).id ], expires_in: 10.minutes, purpose: :data_export)) }
  }.freeze

  # Telas fotografadas com os blocos recolhidos (`<details>`) abertos, para mostrar o que há dentro.
  ABERTAS = %w[ficha-com-contatos].freeze

  # Telas longas, fotografadas com a janela mais alta para mostrar o que importa (o histórico, o formulário).
  ALTAS = %w[ficha-com-acionamentos ficha-com-contatos politica-de-correcao exportacao-de-dados guarda-de-dados].freeze

  test "recria as fotos do README" do
    TELAS.each do |nome, caminho|
      page.driver.resize(1440, ALTAS.include?(nome) ? 1700 : 900)
      visit instance_exec(&caminho)
      assert_selector "h1"
      page.execute_script("document.querySelectorAll('main details').forEach((d) => d.open = true)") if ABERTAS.include?(nome)
      page.save_screenshot(Rails.root.join("tmp/capturas/#{nome}.png").to_s)
    end
  end
end
