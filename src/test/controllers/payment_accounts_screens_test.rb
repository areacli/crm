require "test_helper"

# Telas das contas de pagamento (12, R259 a R270): permissão 14 por credor, V10, formulário do manifesto, segredos que não voltam, histórico sem valores.
class PaymentAccountsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @channel = make_channel(@alfa)
    @beta_channel = make_channel(@beta, code: "BETA-1")
  end

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def account_params(overrides = {})
    { tenant_id: @alfa.id, channel_id: @channel.id, modality: "boleto", provider: "fake", environment: "sandbox", nickname: "Boleto Alfa",
      config: { connection_result: "ok", expire_days: "7" }, secrets: { api_key: "chave-1" } }.deep_merge(overrides)
  end

  test "operador não vê a aba nem as contas (404 registrado) (R267)" do
    entrar(users(:carlos))
    get settings_payment_accounts_path
    assert_response :not_found
    get new_settings_payment_account_path
    assert_response :not_found
    assert_operator AccessEvent.where(event: "access_denied").count, :>=, 2
  end

  test "a aba Contas de pagamento aparece para quem tem a permissão 14 e a de canais continua da 4 (R267)" do
    entrar(users(:joana))
    get settings_payment_accounts_path
    assert_response :success
    assert_select "nav.abas a", text: "Contas de pagamento"
    only_settings = make_user(@alfa, %w[view_portfolio change_settings])
    delete session_path
    entrar(only_settings)
    get settings_channels_path
    assert_select "nav.abas a", text: "Contas de pagamento", count: 0
    get settings_payment_accounts_path
    assert_response :not_found
  end

  test "lista só os credores da permissão 14 e o link direto de outro credor responde 404 registrado (R267, V10)" do
    mine = make_account(@alfa, nickname: "Minha")
    theirs = make_account(@beta, nickname: "Da Beta")
    entrar(users(:joana))
    get settings_payment_accounts_path
    assert_select "th a", text: "Minha"
    assert_select "th a", text: "Da Beta", count: 0
    get edit_settings_payment_account_path(theirs)
    assert_response :not_found
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id
    patch settings_payment_account_path(theirs), params: { payment_account: { nickname: "x" } }
    assert_response :not_found
    delete settings_payment_account_path(theirs)
    post settings_payment_account_activation_path(theirs)
    delete settings_payment_account_activation_path(theirs)
    post settings_payment_account_webhook_secret_path(theirs)
    post settings_payment_account_connection_test_path(theirs)
    assert PaymentAccount.exists?(theirs.id)
    assert_equal "Da Beta", theirs.reload.nickname
    assert_nil theirs.reload.secrets["webhook_secret"]
    assert_nil theirs.last_tested_at
    assert theirs.active?
    assert_not_nil mine
  end

  test "criar conta em credor sem a permissão responde 404 (R267)" do
    entrar(users(:joana))
    post settings_payment_accounts_path, params: { payment_account: account_params(tenant_id: @beta.id, channel_id: @beta_channel.id) }
    assert_response :not_found
    assert_equal 0, PaymentAccount.where(tenant_id: @beta.id).count
  end

  test "quem tem a 14 nos dois credores vê as contas dos dois, com a coluna Credor (R267)" do
    user = make_user(@alfa, %w[view_portfolio change_financial_policies])
    Membership.create!(user: user, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Fin", permissions: %w[view_portfolio change_financial_policies]))
    make_account(@alfa, nickname: "Alfa 1")
    make_account(@beta, nickname: "Beta 1")
    entrar(user)
    get settings_payment_accounts_path
    assert_select "th a", text: "Beta 1"
    assert_select "th", text: "Credor"
  end

  test "o passo de escolha mostra o formulário montado pelo manifesto do fornecedor (R259)" do
    entrar(users(:joana))
    get new_settings_payment_account_path
    assert_select "h2", text: "Credor, modalidade e fornecedor"
    assert_select "form[action='#{settings_payment_accounts_path}']", count: 0
    get new_settings_payment_account_path(tenant_id: @alfa.id, modality: "pix", provider: "efi")
    assert_select "input[type=file][name='payment_account[files][certificate]']"
    assert_select "input[type=password][name='payment_account[secrets][client_secret]']"
    assert_select "input[name='payment_account[config][pix_key]']"
    assert_select "input[name='payment_account[config][payee_code]']", count: 0
    assert_select "form[enctype='multipart/form-data']"
    get new_settings_payment_account_path(tenant_id: @alfa.id, modality: "boleto", provider: "efi")
    assert_select "input[type=file]", count: 0
    assert_select "input[name='payment_account[config][write_off_days]']"
    get new_settings_payment_account_path(tenant_id: @alfa.id, modality: "card", provider: "fake")
    assert_select "input[name='payment_account[config][max_installments]']"
    assert_select "select[name='payment_account[config][connection_result]']"
  end

  test "cadastra a conta, cifra o segredo e registra sem valor (R260, R261, R262, R268)" do
    entrar(users(:joana))
    secret = sentinel("cadastro")
    post settings_payment_accounts_path, params: { payment_account: account_params(secrets: { api_key: secret }) }
    account = PaymentAccount.find_by!(nickname: "Boleto Alfa")
    assert_redirected_to edit_settings_payment_account_path(account)
    assert_equal secret, account.secrets["api_key"]
    assert_equal 7, account.config["expire_days"]
    assert_not_includes account.secrets_before_type_cast, secret
    change = Change.where(subject_type: "payment_account", subject_id: account.id).last
    assert_equal [ "created", "nickname", "Boleto Alfa" ], [ change.event, change.field, change.after ]
    assert_empty Change.where(subject_id: account.id).select { |c| [ c.before, c.after, c.note ].compact.any? { |text| text.include?(secret) } }
    follow_redirect!
    assert_not_includes response.body, secret
    assert_select "small", text: /Definido \(não é mostrado\)/
  end

  test "segredo vazio mantém o valor e preenchido troca, com histórico sem o valor (R261, R268)" do
    account = make_account(@alfa, nickname: "Edita", secrets: { "api_key" => "original" })
    entrar(users(:joana))
    patch settings_payment_account_path(account), params: { payment_account: { nickname: "Edita", channel_id: @channel.id, secrets: { api_key: "" }, config: { expire_days: "9" } } }
    assert_redirected_to edit_settings_payment_account_path(account)
    assert_equal "original", account.reload.secrets["api_key"]
    assert_empty Change.where(subject_id: account.id, event: "secret_replaced")
    assert_equal [ "5", "9" ], Change.where(subject_id: account.id, event: "updated", field: "expire_days").pluck(:before, :after).first

    novo = sentinel("troca")
    patch settings_payment_account_path(account), params: { payment_account: { nickname: "Edita", channel_id: @channel.id, secrets: { api_key: novo } } }
    assert_equal novo, account.reload.secrets["api_key"]
    change = Change.where(subject_id: account.id, event: "secret_replaced").last
    assert_equal [ "api_key", nil, nil ], [ change.field, change.before, change.after ]
    follow_redirect!
    assert_not_includes response.body, novo
    assert_not_includes response.body, "original"
    assert_select "td", text: "Chave de API"
  end

  test "dados inválidos voltam ao formulário com a mensagem e nada é gravado (R259)" do
    entrar(users(:joana))
    post settings_payment_accounts_path, params: { payment_account: account_params(config: { expire_days: "999" }, secrets: { api_key: "" }) }
    assert_response :unprocessable_content
    assert_select "aside[role=alert]", text: /Dias de validade deve estar entre 1 e 365/
    assert_select "aside[role=alert]", text: /Chave de API é obrigatório/
    assert_equal 0, PaymentAccount.count
  end

  test "segunda conta ativa da mesma modalidade e ambiente é recusada; ativar a desativada também enquanto há outra (R260)" do
    make_account(@alfa, nickname: "Primeira", environment: "production")
    entrar(users(:joana))
    post settings_payment_accounts_path, params: { payment_account: account_params(environment: "production", nickname: "Segunda") }
    assert_response :unprocessable_content
    assert_select "aside[role=alert]", text: /Já existe uma conta de Boleto ativa neste ambiente \(Produção\)/

    parked = make_account(@alfa, nickname: "Parada", environment: "production", active: false)
    post settings_payment_account_activation_path(parked)
    assert_redirected_to edit_settings_payment_account_path(parked)
    assert_not parked.reload.active?
    assert_match(/Já existe uma conta de Boleto ativa/, flash[:alert])
  end

  test "desativar e ativar registram o ato (R268)" do
    account = make_account(@alfa)
    entrar(users(:joana))
    delete settings_payment_account_activation_path(account)
    assert_not account.reload.active?
    post settings_payment_account_activation_path(account)
    assert account.reload.active?
    assert_equal %w[deactivated activated], Change.where(subject_id: account.id, subject_type: "payment_account", field: "active").order(:id).pluck(:event)
  end

  test "enviar certificado: o válido mostra titular, validade e impressão digital e não vaza conteúdo nem senha (R263)" do
    account = make_account(@alfa, modality: "pix", nickname: "Pix Alfa", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    entrar(users(:joana))
    senha = sentinel("senha-p12")
    patch settings_payment_account_path(account), params: { payment_account: { nickname: "Pix Alfa", channel_id: @channel.id, secrets: { certificate_password: senha },
                                                                              files: { certificate: p12_upload(subject: "CN=Escola Alfa", days: 90, password: senha) } } }
    assert_redirected_to edit_settings_payment_account_path(account)
    follow_redirect!
    assert_select "dd", text: "CN=Escola Alfa"
    assert_select "dd", text: (Date.current + 90).strftime("%d/%m/%Y")
    assert_select "dd code", text: /\A([0-9A-F]{2}:){31}[0-9A-F]{2}\z/
    assert_not_includes response.body, senha
    assert_equal [ "certificate" ], Change.where(subject_id: account.id, event: "file_replaced").pluck(:field)
    assert_equal [ "certificate_password" ], Change.where(subject_id: account.id, event: "secret_replaced").pluck(:field)
  end

  test "certificado vencido, sem chave, corrompido ou com senha errada é recusado e nada muda (R263)" do
    account = make_account(@alfa, modality: "pix", nickname: "Pix Alfa", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    entrar(users(:joana))
    [ p12_upload(days: -3), p12_upload(with_key: false), p12_upload(password: "certa") ].each do |upload|
      patch settings_payment_account_path(account), params: { payment_account: { nickname: "Pix Alfa", channel_id: @channel.id, secrets: { certificate_password: "errada" }, files: { certificate: upload } } }
      assert_response :unprocessable_content
      assert_select "aside[role=alert]", text: /Certificado \(\.p12\):/
    end
    assert_empty account.reload.file_details
    assert_not account.secret_set?("certificate")
  end

  test "gerar o segredo do webhook mostra uma vez, no-store, e depois só 'Definido' (R265)" do
    account = make_account(@alfa)
    entrar(users(:joana))
    post settings_payment_account_webhook_secret_path(account)
    assert_redirected_to edit_settings_payment_account_path(account)
    follow_redirect!
    assert_equal "no-store", response.headers["Cache-Control"]
    secret = account.reload.secrets["webhook_secret"]
    assert_includes response.body, secret
    get edit_settings_payment_account_path(account)
    assert_not_includes response.body, secret
    assert_select "dd", text: "Definido (não é mostrado de novo)"
    assert_equal "webhook_secret_generated", Change.where(subject_id: account.id).order(:id).last.event
    post settings_payment_account_webhook_secret_path(account)
    assert_equal 2, account.reload.webhook_secrets.size
  end

  test "testar a conexão: o falso responde conforme a configuração e a Efí autentica de verdade (R266)" do
    ok = make_account(@alfa, nickname: "Boa")
    refused = make_account(@alfa, nickname: "Recusada", modality: "card", config: { "connection_result" => "refused" })
    efi = @alfa.payment_accounts.build(channel: @channel, modality: "boleto", provider: "efi", environment: "production", nickname: "Efí")
    efi.assign_values(secrets: { "client_id" => "i", "client_secret" => "s" })
    efi.save!
    entrar(users(:joana))

    post settings_payment_account_connection_test_path(ok)
    follow_redirect!
    assert_match(/Conexão com o fornecedor conferida/, response.body)
    assert_equal "ok", ok.reload.last_test_status

    post settings_payment_account_connection_test_path(refused)
    follow_redirect!
    assert_select "[role=alert]", text: /Credencial recusada pelo fornecedor/
    assert_equal "failed", refused.reload.last_test_status
    assert_equal "tested", Change.where(subject_id: refused.id).order(:id).last.event

    use_efi_client(efi_client.on(:post, "/v1/authorize", status: 401, body: {}))
    post settings_payment_account_connection_test_path(efi)
    follow_redirect!
    assert_match(/Credencial recusada pela Efí/, response.body)
    assert_equal "failed", efi.reload.last_test_status
  end

  test "a conta que já emitiu instrumento só se desativa: sem botão Apagar e a exclusão é recusada (R269)" do
    account = make_account(@alfa, nickname: "Emitiu")
    Payments::Issuer.new.request(tenant: @alfa, kind: "boleto", amount_cents: 1_000, customer: make_customer(@alfa), due_on: Date.current + 5, environment: "sandbox")
    entrar(users(:joana))
    get edit_settings_payment_account_path(account)
    assert_select "button", text: /Apagar/, count: 0
    delete settings_payment_account_path(account)
    assert PaymentAccount.exists?(account.id)
    assert_match(/não se apaga/i, flash[:alert].to_s)
  end

  test "apagar a conta registra o ato e o canal com conta não se apaga (R269)" do
    account = make_account(@alfa, nickname: "Some")
    entrar(users(:joana))
    delete settings_channel_path(@channel)
    assert PaymentChannel.exists?(@channel.id)
    delete settings_payment_account_path(account)
    assert_redirected_to settings_payment_accounts_path
    assert_not PaymentAccount.exists?(account.id)
    assert_equal "deleted", Change.where(subject_type: "payment_account", subject_id: account.id).order(:id).last.event
    delete settings_channel_path(@channel)
    assert_not PaymentChannel.exists?(@channel.id)
  end

  test "o histórico mostra antes e depois dos campos comuns e só o nome dos secretos (R268)" do
    account = make_account(@alfa, nickname: "Hist")
    entrar(users(:joana))
    patch settings_payment_account_path(account), params: { payment_account: { nickname: "Hist 2", channel_id: @channel.id, config: { expire_days: "12" }, secrets: { api_key: sentinel("h") } } }
    get edit_settings_payment_account_path(account)
    assert_select "section[aria-labelledby=historico] td", text: "Hist 2"
    assert_select "section[aria-labelledby=historico] td", text: "Dias de validade"
    assert_select "section[aria-labelledby=historico] td", text: "12"
    assert_select "section[aria-labelledby=historico] td", text: "Segredo trocado"
  end

  test "fornecedor que deixou de existir aparece com aviso e não quebra a lista (caso de exceção)" do
    account = make_account(@alfa, nickname: "Orfã")
    account.update_columns(provider: "extinto")
    entrar(users(:joana))
    get settings_payment_accounts_path
    assert_response :success
    assert_select "td", text: "extinto"
    get edit_settings_payment_account_path(account)
    assert_response :success
    assert_select "aside", text: /não está mais instalado/
  end
end
