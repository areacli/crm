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
    get settings_channels_path, headers: TRECHO
    assert_response :not_found
    get new_settings_payment_account_path, headers: TRECHO
    assert_response :not_found
    assert_operator AccessEvent.where(event: "access_denied").count, :>=, 2
  end

  test "Métodos de recebimento mostra os meios de cada método, e as integrações ficam em Meios de pagamento (16, R373, R373d)" do
    make_account(@alfa, nickname: "Boleto do método")
    entrar(users(:joana))
    configuracao = submenu_do_menu("Configuração")
    assert_equal configuracao.index("Métodos de recebimento") + 1, configuracao.index("Meios de pagamento")
    assert_not_includes configuracao, "Contas de pagamento"
    get settings_channels_path, headers: TRECHO
    assert_response :success
    assert_select "th", text: "Meios"
    assert_select "td a[href=?]", settings_payment_methods_path(credor: @alfa.id), text: "Boleto"
    assert_select "a", text: "Boleto do método", count: 0
    assert_select "a", text: "Criar integração", count: 0
    only_settings = make_user(@alfa, %w[view_portfolio change_settings])
    delete session_path
    entrar(only_settings)
    assert_not_includes submenu_do_menu("Configuração"), "Meios de pagamento"
    get settings_channels_path, headers: TRECHO
    assert_response :success
    assert_select "td", text: /Boleto/
    assert_select "td a", text: "Boleto", count: 0
    get settings_payment_methods_path, headers: TRECHO
    assert_response :not_found
    only_financial = make_user(@alfa, %w[view_portfolio change_financial_policies], email: "fin@alfa.test")
    delete session_path
    entrar(only_financial)
    get settings_channels_path, headers: TRECHO
    assert_response :success
    assert_select "td a", text: "Boleto"
    assert_select "th a", text: @channel.code, count: 0
    assert_select "button", text: "Criar método de recebimento", count: 0
  end

  test "a página própria das contas de pagamento não existe mais (16, R373)" do
    entrar(users(:joana))
    get "/configuracao/contas-de-pagamento", headers: TRECHO
    assert_response :not_found
    get "/configuracao/canais-de-recebimento", headers: TRECHO
    assert_response :not_found
  end

  test "lista só os credores da permissão 14 e o link direto de outro credor responde 404 registrado (R267, V10)" do
    mine = make_account(@alfa, nickname: "Minha")
    theirs = make_account(@beta, nickname: "Da Beta")
    entrar(users(:joana))
    get settings_payment_methods_path, headers: TRECHO
    assert_select "td a", text: "Minha"
    assert_select "td a", text: "Da Beta", count: 0
    get settings_payment_methods_path(credor: @beta.id), headers: TRECHO
    assert_response :not_found
    get edit_settings_payment_account_path(theirs), headers: TRECHO
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
    # Um credor por vez (R373a): o filtro Credor sem "Todos".
    get settings_payment_methods_path, headers: TRECHO
    assert_select "select[name=credor] option", count: 2
    assert_select "select[name=credor] option", text: "Todos", count: 0
    get settings_payment_methods_path(credor: @alfa.id), headers: TRECHO
    assert_select "td a", text: "Alfa 1"
    assert_select "td a", text: "Beta 1", count: 0
    get settings_payment_methods_path(credor: @beta.id), headers: TRECHO
    assert_select "td a", text: "Beta 1"
    assert_select "td a", text: "Alfa 1", count: 0
  end

  test "a integração nova pelo meio: só os fornecedores que emitem o meio, cada um com o que pede, e os campos em Acesso e Cobrança (16, R373b; 12, R259)" do
    entrar(users(:joana))
    get new_settings_payment_account_path(credor: @alfa.id, meio: "pix", ambiente: "homologacao"), headers: TRECHO
    assert_select "h1", text: "Nova integração: Pix"
    assert_select "input[type=hidden][name='payment_account[environment]'][value=sandbox]"
    assert_select "input[type=radio][name='payment_account[provider]']", count: Payments::Providers.for_modality("pix").size
    assert_select "#fornecedores-da-integracao label", text: /Efí.*certificado \.p12/m
    assert_select "input[name='payment_account[nickname]']", count: 0
    get new_settings_payment_account_path(credor: @alfa.id, meio: "boleto", ambiente: "producao"), headers: TRECHO
    assert_select "input[type=radio][value=efi]"
    assert_select "input[type=radio][value=bradesco]", count: 0 # o boleto do Bradesco espera a autenticação (12, R284j)
    # A escolha do fornecedor pede só os blocos que dependem dela, para entrar no lugar dos atuais; o apelido vem sugerido.
    get new_settings_payment_account_path(payment_account: { tenant_id: @alfa.id, modality: "pix", environment: "sandbox", provider: "efi" }), headers: TRECHO
    assert_select "[id=fornecedores-da-integracao][data-fora-de-banda=true] input[type=radio][value=efi][checked]"
    assert_select "[id=campos-da-integracao][data-fora-de-banda=true] input[name='payment_account[nickname]'][value=?]", "Pix Efí homologação"
    assert_select "h1", count: 0
    # O apelido que a pessoa digitou fica; a sugestão que ela não mexeu acompanha a troca do fornecedor.
    get new_settings_payment_account_path(payment_account: { tenant_id: @alfa.id, modality: "pix", environment: "sandbox", provider: "fake", nickname: "Pix Efí homologação", nickname_suggested: "Pix Efí homologação" }), headers: TRECHO
    assert_select "input[name='payment_account[nickname]'][value=?]", "Pix Fornecedor de teste (falso) homologação"
    get new_settings_payment_account_path(payment_account: { tenant_id: @alfa.id, modality: "pix", environment: "sandbox", provider: "fake", nickname: "Meu Pix", nickname_suggested: "Pix Efí homologação" }), headers: TRECHO
    assert_select "input[name='payment_account[nickname]'][value=?]", "Meu Pix"
    get new_settings_payment_account_path(credor: @alfa.id, meio: "pix", ambiente: "homologacao", fornecedor: "efi"), headers: TRECHO
    groups = css_select("fieldset").to_h { |fieldset| [ fieldset.at_css("legend")&.text.to_s.strip, fieldset ] }
    assert_equal [ "Fornecedor", "Acesso", "Cobrança" ], groups.keys
    assert groups["Acesso"].at_css("input[type=file][name='payment_account[files][certificate]']")
    assert groups["Acesso"].at_css("input[type=password][name='payment_account[secrets][client_secret]']")
    assert groups["Acesso"].at_css("input[name='payment_account[config][pix_key]']")
    assert groups["Cobrança"].at_css("input[name='payment_account[config][expire_days]']")
    assert_nil groups["Acesso"].at_css("input[name='payment_account[config][expire_days]']")
    assert_select "input[name='payment_account[config][payee_code]']", count: 0
    assert_select "form[enctype='multipart/form-data']"
    # Com um método de recebimento só, ele já vem escolhido.
    assert_select "select[name='payment_account[channel_id]'] option[selected]" if @alfa.payment_channels.where(active: true).one?
    get new_settings_payment_account_path(credor: @alfa.id, meio: "boleto", ambiente: "homologacao", fornecedor: "efi"), headers: TRECHO
    assert_select "input[type=file]", count: 0
    assert_select "input[name='payment_account[config][write_off_days]']"
    get new_settings_payment_account_path(credor: @alfa.id, meio: "cartao", ambiente: "homologacao", fornecedor: "fake"), headers: TRECHO
    assert_select "h1", text: "Nova integração: Cartão de crédito"
    assert_select "input[name='payment_account[config][max_installments]']"
    assert_select "select[name='payment_account[config][connection_result]']"
    # Sem o quadro (um endereço antigo), a página pede credor, meio e ambiente.
    get new_settings_payment_account_path, headers: TRECHO
    assert_select "select[name='payment_account[modality]']"
    assert_select "#fornecedores-da-integracao p.vazio", text: /Escolha o meio de pagamento/
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
    seguir_redirecionamento!
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
    seguir_redirecionamento!
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
    seguir_redirecionamento!
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
    seguir_redirecionamento!
    assert_equal "no-store", response.headers["Cache-Control"]
    secret = account.reload.secrets["webhook_secret"]
    assert_includes response.body, secret
    get edit_settings_payment_account_path(account), headers: TRECHO
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

    post settings_payment_account_connection_test_path(ok), headers: TRECHO
    assert_match(/Conexão com o fornecedor conferida/, evento_da_spa["aviso"])
    assert_nil evento_da_spa["tom"]
    assert_equal "ok", ok.reload.last_test_status

    post settings_payment_account_connection_test_path(refused), headers: TRECHO
    assert_match(/Credencial recusada pelo fornecedor/, evento_da_spa["aviso"])
    assert_equal "danger", evento_da_spa["tom"]
    assert_equal "failed", refused.reload.last_test_status
    assert_equal "tested", Change.where(subject_id: refused.id).order(:id).last.event

    use_efi_client(efi_client.on(:post, "/v1/authorize", status: 401, body: {}))
    post settings_payment_account_connection_test_path(efi), headers: TRECHO
    assert_match(/Credencial recusada pela Efí/, evento_da_spa["aviso"])
    assert_equal "failed", efi.reload.last_test_status
  end

  test "a conta que já emitiu instrumento só se desativa: sem botão Apagar e a exclusão é recusada (R269)" do
    account = make_account(@alfa, nickname: "Emitiu")
    Payments::Issuer.new.request(tenant: @alfa, kind: "boleto", amount_cents: 1_000, customer: (maria = make_customer(@alfa)), object: bill_for(maria), due_on: Date.current + 5, environment: "sandbox")
    entrar(users(:joana))
    get edit_settings_payment_account_path(account), headers: TRECHO
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
    assert_redirected_to settings_payment_methods_path(credor: @alfa.id)
    assert_not PaymentAccount.exists?(account.id)
    assert_equal "deleted", Change.where(subject_type: "payment_account", subject_id: account.id).order(:id).last.event
    delete settings_channel_path(@channel)
    assert_not PaymentChannel.exists?(@channel.id)
  end

  test "o histórico mostra antes e depois dos campos comuns e só o nome dos secretos (R268)" do
    account = make_account(@alfa, nickname: "Hist")
    entrar(users(:joana))
    patch settings_payment_account_path(account), params: { payment_account: { nickname: "Hist 2", channel_id: @channel.id, config: { expire_days: "12" }, secrets: { api_key: sentinel("h") } } }
    get edit_settings_payment_account_path(account), headers: TRECHO
    assert_select "section[aria-labelledby=historico] td", text: "Hist 2"
    assert_select "section[aria-labelledby=historico] td", text: "Dias de validade"
    assert_select "section[aria-labelledby=historico] td", text: "12"
    assert_select "section[aria-labelledby=historico] td", text: "Segredo trocado"
  end

  test "fornecedor que deixou de existir aparece com aviso e não quebra a lista (caso de exceção)" do
    account = make_account(@alfa, nickname: "Orfã")
    account.update_columns(provider: "extinto")
    entrar(users(:joana))
    get settings_payment_methods_path, headers: TRECHO
    assert_response :success
    assert_select "td", text: "extinto"
    get edit_settings_payment_account_path(account), headers: TRECHO
    assert_response :success
    assert_select "aside", text: /não está mais instalado/
  end

  test "Meios de pagamento: um quadro por meio, uma linha por ambiente, a ativa ou Criar integração, e as desativadas no detalhe (16, R373a)" do
    make_account(@alfa, nickname: "Boleto ativo", environment: "production")
    make_account(@alfa, nickname: "Boleto antigo", environment: "production", active: false)
    entrar(users(:joana))
    get settings_payment_methods_path, headers: TRECHO
    assert_response :success
    assert_select "h1", text: "Meios de pagamento"
    assert_equal [ "Boleto", "Pix", "Cartão de crédito" ], css_select("section.cartao > header h2").map { |title| title.text.strip }
    boleto = css_select("section[aria-labelledby=meio-boleto]").first
    assert_equal "Produção: Fornecedor de teste (falso) · Homologação: não emite", boleto.at_css("header p").text.strip
    rows = boleto.css("table[data-detalhes] > tbody > tr:not(.detalhe-da-linha)")
    assert_equal [ "Produção", "Homologação" ], rows.map { |row| row.at_css("th").text.strip }
    assert_includes rows[0].text, "Boleto ativo"
    assert_includes rows[0].text, "Credenciais definidas"
    assert_includes rows[1].text, "Não emite"
    assert rows[1].at_css("a[href='#{new_settings_payment_account_path(credor: @alfa.id, meio: "boleto", ambiente: "homologacao")}']"), "Criar integração com o meio e o ambiente da linha"
    assert_includes boleto.at_css("tr.detalhe-da-linha").text, "Boleto antigo"
    pix = css_select("section[aria-labelledby=meio-pix]").first
    assert_equal 2, pix.css("a").count { |link| link.text.strip == "Criar integração" }
    assert rows[0].at_css("a[href='#{new_settings_payment_account_path(substitui: PaymentAccount.find_by!(nickname: "Boleto ativo").id)}']"), "Trocar fornecedor na linha ativa"
  end

  test "trocar fornecedor com credenciais: a nova entra e a anterior sai no mesmo ato, e o que ela emitiu continua com ela (16, R373c)" do
    old = make_account(@alfa, nickname: "Boleto de teste")
    entrar(users(:joana))
    get new_settings_payment_account_path(substitui: old.id), headers: TRECHO
    assert_select "h1", text: "Trocar fornecedor: Boleto"
    assert_select "aside", text: /A integração Boleto de teste deixa de emitir boleto em homologação quando a troca terminar\. Ela não tem instrumento vigente\./
    assert_select "input[type=radio][value=fake]", count: 0
    assert_select "input[type=radio][value=efi]"
    post settings_payment_accounts_path, params: { payment_account: { replaces_id: old.id, tenant_id: @alfa.id, channel_id: @channel.id, modality: "boleto", provider: "efi", environment: "sandbox",
                                                                      nickname: "Boleto Efí homologação", secrets: { client_id: "id", client_secret: "segredo" } } }
    created = PaymentAccount.find_by!(nickname: "Boleto Efí homologação")
    assert_redirected_to edit_settings_payment_account_path(created)
    assert created.active?
    assert_equal old.id, created.replaces_id
    assert_not old.reload.active?
    assert_equal "replaced", Change.where(subject_type: "payment_account", subject_id: old.id).order(:id).last.event
    assert_equal "replacing", Change.where(subject_type: "payment_account", subject_id: created.id).order(:id).last.event
    # Só a ativa se troca.
    post settings_payment_accounts_path, params: { payment_account: { replaces_id: old.id, tenant_id: @alfa.id, channel_id: @channel.id, modality: "boleto", provider: "fake", environment: "sandbox",
                                                                      nickname: "Outra troca", config: { connection_result: "ok" }, secrets: { api_key: "x" } } }
    assert_response :unprocessable_content
    assert_not PaymentAccount.exists?(nickname: "Outra troca")
    assert created.reload.active?
  end

  test "trocar para fornecedor de conexão por autorização: a anterior continua até a conexão; Desistir exclui a nova (16, R373c)" do
    old = make_account(@alfa, nickname: "Boleto de teste")
    entrar(users(:joana))
    get new_settings_payment_account_path(substitui: old.id, payment_account: { replaces_id: old.id, provider: "pagbank" }), headers: TRECHO
    assert_select "aside", text: /Até a conexão voltar, boleto continua pela integração Boleto de teste/
    post settings_payment_accounts_path, params: { payment_account: { replaces_id: old.id, tenant_id: @alfa.id, channel_id: @channel.id, modality: "boleto", provider: "pagbank", environment: "sandbox",
                                                                      nickname: "Boleto PagBank homologação" } }
    created = PaymentAccount.find_by!(nickname: "Boleto PagBank homologação")
    assert_not created.active?
    assert old.reload.active?
    assert created.waiting_replacement?
    get settings_payment_methods_path, headers: TRECHO
    boleto = css_select("section[aria-labelledby=meio-boleto]").first
    assert_includes boleto.text, "À espera da conexão"
    assert_includes boleto.text, "Desistir"
    get edit_settings_payment_account_path(created), headers: TRECHO
    assert_select "aside", text: /Troca de Boleto de teste à espera da conexão/
    delete settings_payment_account_path(created)
    assert_not PaymentAccount.exists?(created.id)
    assert old.reload.active?
  end
end
