require "test_helper"

# Telas de pagamentos: permissões 4, 5, 6, 14 e 17 por credor, isolamento (V10), canais, políticas, importações, ficha e resumo.
class PaymentsScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @channel = make_channel(@alfa)
    @beta_channel = make_channel(@beta, code: "BETA-1")
  end

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "operador não vê canais, políticas nem importação de pagamentos (404 registrado)" do
    entrar(users(:carlos))
    [ settings_channels_path, settings_payment_policy_path, new_import_path(kind: "payments"), new_import_path(kind: "reversals") ].each do |path|
      get path
      assert_response :not_found, path
    end
    assert_operator AccessEvent.where(event: "access_denied").count, :>=, 4
  end

  test "lista de canais mostra só os credores da permissão 4 (V10) e o link direto de outro credor responde 404 registrado" do
    entrar(users(:joana))
    get settings_channels_path
    assert_response :success
    assert_select "th a", text: @channel.code
    assert_select "th a", text: "BETA-1", count: 0
    get edit_settings_channel_path(@beta_channel)
    assert_response :not_found
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id
    patch settings_channel_path(@beta_channel), params: { payment_channel: { description: "x", kind: "card", code: "Z", active: "1" } }
    assert_response :not_found
    delete settings_channel_path(@beta_channel)
    assert_response :not_found
    assert PaymentChannel.exists?(@beta_channel.id)
  end

  test "quem tem a permissão 4 nos dois credores vê os dois, com a coluna Credor" do
    user = make_user(@alfa, %w[change_settings])
    Membership.create!(user: user, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Cfg", permissions: %w[view_portfolio change_settings]))
    entrar(user)
    get settings_channels_path
    assert_select "th a", text: "BETA-1"
    assert_select "th", text: "Credor"
  end

  test "cadastra, edita e apaga um canal; tudo fica registrado (R45)" do
    entrar(users(:joana))
    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "card", code: "1029384756", description: "Cielo" } }
    assert_redirected_to settings_channels_path
    channel = PaymentChannel.find_by!(code: "1029384756")
    assert_equal "created", Change.where(subject_type: "channel", subject_id: channel.id).last.event

    patch settings_channel_path(channel), params: { payment_channel: { kind: "account", code: "NOVO", description: "Cielo loja", active: "1" } }
    assert_equal [ "NOVO", "Cielo loja", "account" ], channel.reload.values_at(:code, :description, :kind).map(&:to_s)
    assert_includes Change.where(subject_id: channel.id, event: "updated").pluck(:field), "description"

    delete settings_channel_path(channel)
    assert_redirected_to settings_channels_path
    assert_not PaymentChannel.exists?(channel.id)
    assert_equal "deleted", Change.where(subject_type: "channel", subject_id: channel.id).last.event
  end

  test "código repetido no credor é recusado; o mesmo código em outro credor vale" do
    entrar(users(:joana))
    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "account", code: @channel.code, description: "Repetido" } }
    assert_response :unprocessable_content
    assert_equal 1, PaymentChannel.where(code: @channel.code).count
    assert_equal 2, PaymentChannel.where(code: [ @channel.code, "BETA-1" ]).count
  end

  test "canal com pagamento: o código não muda, só se desativa e não se apaga" do
    make_bill(@alfa)
    confirm_import(run_payments_import([ payment_line ]))
    entrar(users(:joana))
    patch settings_channel_path(@channel), params: { payment_channel: { kind: "account", code: "OUTRO", description: "Nova descrição", active: "0" } }
    @channel.reload
    assert_equal [ PaymentsHelper::CHANNEL_CODE, "Nova descrição", false ], [ @channel.code, @channel.description, @channel.active ]
    delete settings_channel_path(@channel)
    assert_redirected_to root_path
    assert PaymentChannel.exists?(@channel.id)
  end

  test "o segredo do webhook aparece uma só vez na edição" do
    entrar(users(:joana))
    post settings_channel_webhook_secret_path(@channel)
    assert_redirected_to edit_settings_channel_path(@channel)
    follow_redirect!
    secret = @channel.reload.webhook_secret
    assert_includes response.body, secret
    get edit_settings_channel_path(@channel)
    assert_not_includes response.body, secret
    assert_equal "webhook_secret_generated", Change.where(subject_id: @channel.id).last.event
    assert_nil Change.where(subject_id: @channel.id).pluck(:before, :after).flatten.compact.find { |value| value.include?(secret) }
  end

  test "políticas de pagamento: a permissão 14 é separada da 4 e cada mudança fica registrada" do
    entrar(make_user(@alfa, %w[change_settings]))
    get settings_payment_policy_path
    assert_response :not_found

    entrar(users(:joana))
    get settings_payment_policy_path
    assert_response :success
    patch settings_payment_policy_path, params: { tenant_id: @alfa.id, tenant_setting: { partial_payment_policy: "credit", withdrawn_payment_policy: "credit",
                                                                                    withdrawn_reversal_policy: "withdrawn", reversal_month_policy: "payment" } }
    assert_redirected_to settings_payment_policy_path
    setting = @alfa.setting.reload
    assert_equal %w[credit credit withdrawn payment], setting.values_at(*TenantSetting::PAYMENT_POLICIES).map(&:to_s)
    assert_equal 4, Change.where(subject_type: "settings", event: TenantSetting::PAYMENT_POLICIES.map { |f| "#{f}_changed" }).count
    patch settings_payment_policy_path, params: { tenant_id: @beta.id, tenant_setting: { partial_payment_policy: "credit" } }
    assert_response :not_found
    assert_predicate @beta.setting.reload, :partial_payment_policy_partial?
  end

  test "o menu abre a primeira aba de configuração que o usuário vê" do
    entrar(make_user(@alfa, %w[change_financial_policies]))
    get root_path
    assert_select "nav[aria-label=Menu] a[href='#{settings_payment_policy_path}']", text: "Configuração"
    get settings_payment_policy_path
    # Com a 14 também aparecem as abas Contas de pagamento (12), Segmentos, Promessas (10, R206) e Índices (08, R158).
    assert_select "nav.abas a", count: 5
  end

  test "importar pagamentos exige a permissão 5; confirmar, a 6, também por link direto (R47)" do
    uploader = make_user(@alfa, %w[upload_payments])
    make_bill(@alfa)
    entrar(uploader)
    get new_import_path(kind: "payments")
    assert_response :success
    assert_select "h1", "Importar pagamentos"
    get new_import_path(kind: "portfolio")
    assert_response :not_found
    arquivo = fixture_file_upload(write_csv([ payment_line ], header: PaymentsHelper::PAYMENT_HEADER), "text/csv")
    assert_enqueued_with(job: CheckImportJob) { post imports_path, params: { import: { tenant_id: @alfa.id, kind: "payments", file: arquivo } } }
    import = Import.last
    assert_predicate import, :payments?
    perform_enqueued_jobs(only: CheckImportJob)
    get import_path(import)
    assert_response :success
    assert_select "button", text: "Confirmar", count: 0
    post import_confirmation_path(import)
    assert_response :not_found
    assert_predicate import.reload, :checked?
    post import_discard_path(import)
    assert_response :not_found
  end

  test "quem confirma pagamentos (6) confirma, e quem só tem as permissões da carteira não toca nos pagamentos" do
    make_bill(@alfa)
    import = run_payments_import([ payment_line ])
    entrar(make_user(@alfa, %w[upload_imports confirm_imports]))
    get import_path(import)
    assert_response :not_found
    post import_confirmation_path(import)
    assert_response :not_found

    entrar(make_user(@alfa, %w[confirm_payments]))
    get import_path(import)
    assert_select "button", text: "Confirmar"
    assert_enqueued_with(job: ConfirmImportJob) { post import_confirmation_path(import) }
  end

  test "a lista de importações mostra o tipo e filtra por credor e permissão (V10)" do
    make_bill(@alfa)
    run_payments_import([ payment_line ])
    beta_import = Import.create!(tenant: @beta, user: users(:ana), kind: :payments, mode: :incremental, status: :checked, original_name: "beta.csv")
    entrar(users(:joana))
    get imports_path
    assert_select "td", text: "Pagamentos"
    assert_select "td", text: "beta.csv", count: 0
    get import_path(beta_import)
    assert_response :not_found
  end

  test "as planilhas-modelo de pagamentos e de estornos são baixadas" do
    entrar(users(:joana))
    get template_imports_path(kind: "payments")
    assert_response :success
    assert_includes response.body, "canal;identificador;documento;titulo;data_pagamento;valor;meio"
    get template_imports_path(kind: "reversals")
    assert_includes response.body, "identificador_pagamento;identificador_estorno"
  end

  test "ficha: seção Pagos e crédito por contrato, sem saldo do cliente (R54, R55b)" do
    bill = make_bill(@alfa, amount_cents: 50_000)
    confirm_import(run_payments_import([ payment_line("valor" => "650,00") ]))
    customer = bill.customer
    entrar(users(:carlos))
    get customer_path(customer)
    assert_response :success
    assert_select "h2", "Pagos"
    assert_select "h3", text: /CT-1: R\$ 150,00/
    assert_select "button", text: "Transferir crédito", count: 0
    assert_no_match(/saldo de crédito/i, response.body)
  end

  test "transferir crédito pela ficha exige a permissão 17 no credor, vale só no credor e fica registrado" do
    from = make_bill(@alfa, number: "NF-1").contract
    to = make_bill(@alfa, number: "NF-2", contract_code: "C-2", document: JOAO, name: "Pedro").contract
    Credit.create!(tenant: @alfa, contract: from, kind: :entry, amount_cents: 20_000, reason: :excess)
    customer = from.customers.first
    params = { credit_transfer: { from_contract_id: from.id, to_code: "C-2", amount: "150,00", reason: "migração" } }

    entrar(users(:carlos))
    assert_no_difference -> { Credit.count } do
      post customer_credit_transfers_path(customer), params: params
    end
    assert_response :not_found
    assert_equal 1, AccessEvent.where(event: "access_denied").count

    entrar(users(:joana))
    get customer_path(customer)
    assert_select "button", text: "Transferir crédito"
    post customer_credit_transfers_path(customer), params: params
    assert_redirected_to customer_path(customer, anchor: "credito")
    assert_equal [ 5_000, 15_000 ], [ from.credit_cents, to.credit_cents ]
    follow_redirect!
    assert_select "h3", text: /CT-1: R\$ 50,00/

    post customer_credit_transfers_path(customer), params: params.deep_merge(credit_transfer: { reason: "" })
    assert_redirected_to customer_path(customer, anchor: "credito")
    assert_equal 2, Credit.where(reason: :transfer).count
  end

  test "transferência para contrato de outro credor ou com contrato de origem de outro cliente é recusada (V10)" do
    from = make_bill(@alfa, number: "NF-1").contract
    other = make_bill(@beta, number: "NF-9", contract_code: "C-9").contract
    Credit.create!(tenant: @alfa, contract: from, kind: :entry, amount_cents: 20_000, reason: :excess)
    entrar(users(:joana))
    customer = from.customers.first
    post customer_credit_transfers_path(customer), params: { credit_transfer: { from_contract_id: from.id, to_code: "C-9", amount: "10,00", reason: "x" } }
    assert_equal "Contrato de destino não encontrado neste credor.", flash[:alert]
    post customer_credit_transfers_path(customer), params: { credit_transfer: { from_contract_id: other.id, to_code: "C-1", amount: "10,00", reason: "x" } }
    assert_response :not_found
    assert_equal 1, Credit.count
  end

  test "resumo: recuperado por meio, créditos e pendentes, um cartão por credor e o total só dos reais pagos (R58, R58a)" do
    make_bill(@alfa, amount_cents: 100_000)
    make_bill(@beta, amount_cents: 20_000)
    make_channel(@beta)
    confirm_import(run_payments_import([ payment_line("valor" => "1.050,00"), payment_line("identificador" => "P2", "titulo" => "NF-9", "valor" => "30,00", "meio" => "boleto") ]))
    Membership.create!(user: users(:joana), tenant: @beta, profile: profiles(:beta_operator))
    entrar(users(:joana))
    get root_path
    assert_select "h2", text: /Recuperado — Escola Alfa/
    assert_select "h2", text: /Recuperado — Clínica Beta/
    assert_select "h2", "Todos os credores"
    assert_includes response.body, "R$ 1.000,00"
    assert_includes response.body, "Pix R$ 1.000,00"
    assert_select "dt", text: "Pagamentos pendentes"
  end

  test "resumo de quem só consulta a Alfa não mostra nada da Beta (V10)" do
    make_bill(@beta, amount_cents: 20_000)
    entrar(users(:joana))
    get root_path
    assert_select "h2", text: /Beta/, count: 0
  end

  test "lista de clientes diz 'sem títulos em cobrança' para quem só tem títulos pagos" do
    make_bill(@alfa, amount_cents: 100_000)
    confirm_import(run_payments_import([ payment_line ]))
    entrar(users(:carlos))
    get customers_path(q: "maria")
    assert_select "td", text: "sem títulos em cobrança"
  end
end
