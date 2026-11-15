require "test_helper"

# Conexão por autorização (12, revisão 5, R284k e R284l), pela tela e pela renovação: "Conectar" leva o gestor à página do PagBank com um `state` de uso
# único; a volta troca o código pelos tokens; `state` reusado, de outro usuário ou vencido é recusado; a renovação é uma só e, recusada, desconecta e avisa.
class PaymentAccountConnectionsTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    with_pagbank_app
    @previous_url = Rails.configuration.x.payments.public_url
    Rails.configuration.x.payments.public_url = "https://crm.exemplo.com.br"
  end

  teardown { Rails.configuration.x.payments.public_url = @previous_url }

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  def token_response(access: "TOKEN-NOVO", refresh: "RENOVA-NOVO") = { "access_token" => access, "refresh_token" => refresh, "expires_in" => 31_536_000, "account_id" => "ACCO_123" }

  test "a integração mostra o estado da conexão, o botão Conectar fora da casca e a linha do aviso por pedido" do
    account = make_pagbank_account(@alfa, connected: false)
    entrar(users(:joana))
    get edit_settings_payment_account_path(account), headers: TRECHO
    assert_response :success
    assert_select "dd", text: "Não conectada"
    assert_select "a.botao[target=_top][href=?]", new_settings_payment_account_connection_path(account), text: "Conectar ao PagBank"
    assert_select "dd", text: "O endereço do aviso vai em cada pedido"
    assert_select "input[name*=webhook_url_key]", count: 0
  end

  test "sem a aplicação da instalação, a tela avisa e não oferece Conectar" do
    without_pagbank_app
    account = make_pagbank_account(@alfa, connected: false)
    entrar(users(:joana))
    get edit_settings_payment_account_path(account), headers: TRECHO
    assert_select "a", text: "Conectar ao PagBank", count: 0
    assert_match(/não tem a aplicação do PagBank/, response.body)
  end

  test "conectar: vai ao PagBank com o state, volta, troca o código, grava os tokens cifrados e registra sem eles (R284k)" do
    account = make_pagbank_account(@alfa, connected: false)
    client = use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: token_response))
    entrar(users(:joana))
    get new_settings_payment_account_connection_path(account)
    assert_response :see_other
    location = URI.parse(response.location)
    assert_equal "connect.sandbox.pagbank.com.br", location.host
    assert_equal "/oauth2/authorize", location.path
    query = Rack::Utils.parse_query(location.query)
    assert_equal "app-crm-sandbox", query["client_id"]
    assert_equal "https://crm.exemplo.com.br/configuracao/integracoes/conexao/retorno", query["redirect_uri"]
    assert_equal "payments.read payments.create payments.refund", query["scope"]
    assert query["state"].length <= 128

    get settings_payment_account_connection_return_path(state: query["state"], code: "CODIGO-1")
    assert_redirected_to "/#/configuracao/integracoes/#{account.id}/editar"
    account.reload
    assert Payments::Connection.connected?(account)
    assert_equal "TOKEN-NOVO", account.secrets["access_token"]
    assert_equal "ACCO_123", account.config["connection_label"]
    exchange = client.to("/oauth2/token").first
    assert_equal({ "grant_type" => "authorization_code", "code" => "CODIGO-1", "redirect_uri" => "https://crm.exemplo.com.br/configuracao/integracoes/conexao/retorno" }, JSON.parse(exchange.body))
    assert_equal "app-crm-sandbox", exchange.headers["X_CLIENT_ID"]
    assert_equal "Bearer token-plataforma-sandbox", exchange.headers["Authorization"]
    change = Change.where(subject_type: "payment_account", subject_id: account.id, event: "connected").sole
    assert_not_includes change.attributes.values.join(" "), "TOKEN-NOVO"
    assert_not_includes PaymentAccount.connection.select_value("select secrets::text from payment_accounts where id = #{account.id}").to_s, "TOKEN-NOVO", "cifrado em repouso"

    get settings_payment_account_connection_return_path(state: query["state"], code: "CODIGO-1")
    assert_redirected_to "/"
    assert_equal 1, client.to("/oauth2/token").size, "o state não vale duas vezes"
  end

  test "state de outra sessão, vencido ou com autorização negada: nada é gravado" do
    account = make_pagbank_account(@alfa, connected: false)
    client = use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: token_response))
    entrar(users(:joana))
    get settings_payment_account_connection_return_path(state: "inventado", code: "CODIGO-1")
    assert_redirected_to "/"
    get new_settings_payment_account_connection_path(account)
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    travel 11.minutes do
      get settings_payment_account_connection_return_path(state: state, code: "CODIGO-1")
    end
    get new_settings_payment_account_connection_path(account)
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    get settings_payment_account_connection_return_path(state: state, error: "access_denied")
    assert_not Payments::Connection.connected?(account.reload)
    assert_empty client.requests
    assert Change.where(subject_id: account.id, event: "connection_failed").exists?
  end

  test "quem não tem a permissão 14 não começa a conexão" do
    account = make_pagbank_account(@alfa, connected: false)
    entrar(users(:carlos))
    get new_settings_payment_account_connection_path(account)
    assert_response :not_found
  end

  test "desconectar tira os tokens e registra" do
    account = make_pagbank_account(@alfa)
    entrar(users(:joana))
    delete settings_payment_account_connection_path(account), headers: TRECHO
    assert_response :success
    account.reload
    assert_not Payments::Connection.connected?(account)
    assert_nil account.secrets["access_token"]
    assert Change.where(subject_id: account.id, event: "disconnected").exists?
  end

  # 16, revisão 1 (R373c): a troca de fornecedor que esperava a conexão se completa na volta, no mesmo ato.
  test "a volta da conexão completa a troca de fornecedor: a nova entra e a anterior sai" do
    old = make_account(@alfa, nickname: "Boleto de teste", modality: "boleto", environment: "sandbox")
    created = Payments::AccountManager.new(users(:joana)).create(tenant: @alfa, account_code: "0001-99999-0", modality: "boleto", provider: "pagbank", environment: "sandbox",
                                                                 nickname: "Boleto PagBank", replaces: old)
    assert_not created.active?
    use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: token_response))
    entrar(users(:joana))
    get new_settings_payment_account_connection_path(created)
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    get settings_payment_account_connection_return_path(state: query["state"], code: "CODIGO-1")
    assert created.reload.active?
    assert_not old.reload.active?
    assert_equal %w[replaced], Change.where(subject_type: "payment_account", subject_id: old.id).order(:id).pluck(:event).last(1)
    assert_equal "replacement_completed", Change.where(subject_type: "payment_account", subject_id: created.id).order(:id).last.event
  end
end

class PaymentConnectionRenewalTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    with_pagbank_app
  end

  test "token vencendo: uma renovação só, os dois tokens novos gravados juntos (R284l)" do
    account = make_pagbank_account(@alfa, expires_at: 2.minutes.from_now)
    client = use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: { "access_token" => "TOKEN-2", "refresh_token" => "RENOVA-2", "expires_in" => 3600 }))
    connection = Payments::Connection.new
    assert_equal "TOKEN-2", connection.access_token(account)
    assert_equal "TOKEN-2", connection.access_token(account.reload)
    assert_equal({ "grant_type" => "refresh_token", "refresh_token" => "RENOVA-1" }, JSON.parse(client.to("/oauth2/token").sole.body))
    assert_equal "RENOVA-2", account.reload.secrets["refresh_token"]
    assert Change.where(subject_id: account.id, event: "connection_renewed").exists?
  end

  test "401 com um token que outra chamada já renovou não renova de novo" do
    account = make_pagbank_account(@alfa)
    client = use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: { "access_token" => "TOKEN-2", "refresh_token" => "RENOVA-2", "expires_in" => 3600 }))
    connection = Payments::Connection.new
    assert_equal "TOKEN-2", connection.access_token(account, stale: "TOKEN-VENDEDOR-1")
    assert_equal "TOKEN-2", connection.access_token(account.reload, stale: "TOKEN-VENDEDOR-1")
    assert_equal 1, client.to("/oauth2/token").size
  end

  test "a chamada recusada com 401 renova e tenta de novo com o token novo" do
    account = make_pagbank_account(@alfa)
    client = use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", body: { "access_token" => "TOKEN-2", "refresh_token" => "RENOVA-2", "expires_in" => 3600 })
                                              .on(:get, "/orders/") { |request| request.headers["Authorization"] == "Bearer TOKEN-2" ? { status: 200, body: pagbank_order(status: "WAITING") } : { status: 401, body: {} } })
    assert_equal "active", Payments::Providers::Pagbank.new.fetch_pix(account, PagbankHttpHelper::ORDER_ID).status
    assert_equal 2, client.to("/orders/").size
  end

  test "renovação recusada: a integração fica desconectada, o sino avisa e a emissão falha sem chamada" do
    account = make_pagbank_account(@alfa, expires_at: 1.minute.from_now)
    use_pagbank_client(pagbank_client.on(:post, "/oauth2/token", status: 400, body: { "error_messages" => [ { "code" => "invalid_grant" } ] }))
    error = assert_raises(Payments::Providers::Error) { Payments::Connection.new.access_token(account) }
    assert_match(/desconectada/, error.message)
    account.reload
    assert_equal "disconnected", account.config["connection_state"]
    assert_nil account.secrets["refresh_token"]
    assert Notice.where(kind: "payment_connection_lost", user: users(:joana)).exists?
    assert Change.where(subject_id: account.id, event: "connection_lost").exists?
  end
end
