require "test_helper"

# Telas dos direitos do titular (07): ficha, exportação, anonimização, retenção, página de guarda, prazo de guarda e isolamento por credor (V10).
class TitularScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @maria = make_full_customer(@alfa, code: "CT-7")
    @beta_maria = make_full_customer(@beta, code: "CT-7")
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  # Marta: direitos do titular só na Alfa; na Beta, só consulta.
  def marta
    user = make_user(@alfa, %w[handle_data_subject_rights change_settings])
    Membership.create!(user: user, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    user
  end

  test "R141: quem tem a 13 vê Exportar dados e Anonimizar na ficha; quem não tem não vê, e o envio direto é recusado e registrado" do
    entrar(users(:joana))
    get customer_path(@maria)
    assert_select "button", text: "Exportar dados"
    assert_select "button", text: "Anonimizar"

    reader = make_user(@alfa, [])
    delete session_path
    entrar(reader)
    get customer_path(@maria)
    assert_select "button", text: "Exportar dados", count: 0
    assert_select "#anonimizar-cliente", 0
    assert_no_difference "Customer.identified.count" do
      post customer_anonymization_path(@maria), params: { anonymization: { reason: "x", document: @maria.document } }
      assert_response :not_found
      post customer_data_export_path(@maria), params: { export: { reason: "x" } }
      assert_response :not_found
      post customer_retention_path(@maria), params: { retention: { reason: "x" } }
      assert_response :not_found
    end
    assert_equal 3, AccessEvent.where(event: "access_denied", tenant_id: @alfa.id, user_id: reader.id).count
  end

  test "R127 a R129 (critério de aceite): exportar com motivo registra sem o conteúdo e abre a página e o JSON com tudo" do
    entrar(users(:joana))
    post customer_data_export_path(@maria), params: { export: { reason: "pedido do titular por e-mail, protocolo 123" } }
    assert_response :see_other
    follow_redirect!
    assert_response :success

    assert_select "h1", text: /Dados de Maria Souza mantidos por Escola Alfa/
    %w[Cadastro Contatos Contratos Títulos].each { |h| assert_select "h2", text: /#{h}/ }
    assert_select "td, th", text: /987654321|98765-4321/
    assert_select "td", text: /Maria disse que paga dia 10/
    assert_select "td", text: /Mensalidade de Maria Souza|Mensalidade/
    change = Change.find_by!(subject_type: "customer", subject_id: @maria.id, event: "data_exported")
    assert_equal [ users(:joana), "pedido do titular por e-mail, protocolo 123" ], [ change.user, change.note ]
    assert_no_match(/Maria disse/, change.attributes.values.join)

    json_path = css_select("a").find { |a| a.text.include?("Baixar em JSON") }["href"]
    get json_path
    assert_response :success
    assert_match(/attachment; filename="dados-cliente-#{@maria.id}\.json"/, response.headers["Content-Disposition"])
    data = JSON.parse(response.body)
    assert_equal [ "Maria Souza", "529.982.247-25" ], data["cliente"].values_at("nome", "documento")
    assert_equal %w[acionamentos contatos contratos creditos cliente credor divergencias_de_valor estornos exportado_em anonimizado historico pagamentos titulos].sort, data.keys.sort
    assert_equal 2, data["contatos"].size
    assert_equal 1, data["titulos"].size
    assert_equal 1, data["pagamentos"].size
    assert_includes data["acionamentos"].first["texto"], "paga dia 10"
  end

  test "R129: sem motivo a exportação é recusada e nada é registrado" do
    entrar(users(:joana))
    assert_no_difference "Change.count" do
      post customer_data_export_path(@maria), params: { export: { reason: " " } }
    end
    assert_response :see_other
    follow_redirect!
    assert_select "[role=alert], .aviso", text: /Informe o motivo da exportação/
  end

  test "exportação: o endereço assinado vale para quem pediu, para aquele cliente, e vence em 10 minutos" do
    entrar(users(:joana))
    post customer_data_export_path(@maria), params: { export: { reason: "pedido" } }
    path = response.location
    get path
    assert_response :success

    get customer_data_export_path(@maria, token: "adulterado")
    assert_response :not_found
    other = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "Outro")
    get customer_data_export_path(other, token: Rack::Utils.parse_query(URI(path).query)["token"])
    assert_response :not_found
    travel 11.minutes do
      get path
      assert_response :not_found
    end
  end

  test "R127a e R140a (V10, critério de aceite): Marta anonimiza a Maria da Alfa; na Beta, exportar e anonimizar por link direto são recusados e a Beta fica intacta" do
    user = marta
    user.memberships.find_by!(tenant: @alfa).profile.update!(permissions: %w[view_portfolio handle_data_subject_rights change_settings])
    entrar(user)

    post customer_anonymization_path(@maria), params: { anonymization: { reason: "pedido do titular", document: "529.982.247-25" } }
    assert_redirected_to customer_path(@maria)
    assert @maria.reload.anonymized?

    post customer_anonymization_path(@beta_maria), params: { anonymization: { reason: "pedido", document: "529.982.247-25" } }
    assert_response :not_found
    post customer_data_export_path(@beta_maria), params: { export: { reason: "pedido" } }
    assert_response :not_found
    get customer_data_export_path(@beta_maria, token: "x")
    assert_response :not_found
    assert_not @beta_maria.reload.anonymized?
    assert_equal 2, @beta_maria.contacts.count
    assert_operator AccessEvent.where(event: "access_denied", tenant_id: @beta.id, user_id: user.id).count, :>=, 3
  end

  test "R130 e R131: a ficha mostra o que impede; o documento errado é recusado com a mensagem; certo, anonimiza e a ficha mostra o aviso" do
    Credit.create!(tenant: @alfa, contract: @maria.contracts.first, kind: :entry, reason: :excess, amount_cents: 5_000)
    entrar(users(:joana))
    get customer_path(@maria)
    assert_select "#anonimizar-cliente", text: /Não é possível anonimizar: crédito do contrato CT-7 de R\$ 50,00 em aberto/
    assert_select "#anonimizar-cliente button[type=submit]", 0

    post customer_anonymization_path(@maria), params: { anonymization: { reason: "x", document: "529.982.247-25" } }
    follow_redirect!
    assert_select "[role=alert], .aviso", text: /não é possível anonimizar: crédito do contrato CT-7 de R\$ 50,00 em aberto/i

    Credit.create!(tenant: @alfa, contract: @maria.contracts.first, kind: :entry, reason: :excess, amount_cents: -5_000)
    post customer_anonymization_path(@maria), params: { anonymization: { reason: "pedido", document: "111.444.777-35" } }
    follow_redirect!
    assert_select "[role=alert], .aviso", text: /documento digitado não é o deste cliente/
    post customer_anonymization_path(@maria), params: { anonymization: { reason: "pedido", document: "52998224725" } }
    follow_redirect!
    assert_select "h1", text: /Cliente anonimizado nº #{@maria.id}/
    assert_select "main", text: /Cliente anonimizado em #{Date.current.strftime('%d/%m/%Y')}/
    assert_select "#exportar-dados"
    assert_select "#anonimizar-cliente", 0
    assert_select "#corrigir-nome", 0
    assert_select "#contatos button", 0
    assert_select "#acionamentos form", 0
  end

  test "R141: exportar um cliente anonimizado traz só o que restou, sem dado pessoal" do
    Titular::Anonymizer.on_request(@maria, actor: users(:joana), reason: "pedido", document: @maria.document)
    entrar(users(:joana))
    post customer_data_export_path(@maria.reload), params: { export: { reason: "pedido" } }
    follow_redirect!

    assert_select "main", text: /Cliente anonimizado em/
    assert_no_match(/Maria|52998224725|98765/, response.body)
  end

  test "acionamento de cliente anonimizado é recusado" do
    Titular::Anonymizer.on_request(@maria, actor: users(:joana), reason: "pedido", document: @maria.document)
    entrar(users(:joana))

    assert_no_difference "ContactAttempt.count" do
      post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result_of(@alfa, :no_answer).id } }
    end
    assert_response :see_other
  end

  # ---- Página de guarda ----

  test "R138: a página de guarda mostra prazo, previstos, retidos e execuções, só dos credores com a 13" do
    @maria.bill.update!(paid_on: Date.current - 5.years + 10.days)
    @maria.payment.update!(paid_on: Date.current - 5.years + 10.days)
    retido = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "João Retido", ended_on: Date.current - 9.years)
    Titular::Retainer.new(users(:joana)).retain(retido, "ação judicial nº 77")
    TaskRun.create!(tenant: @alfa, name: "data_retention", status: "succeeded", started_at: 1.hour.ago, finished_at: 1.hour.ago, processed: 3)
    TaskRun.create!(tenant: @beta, name: "data_retention", status: "failed", started_at: 1.hour.ago, error_kind: "StatementInvalid")
    user = marta
    user.memberships.find_by!(tenant: @alfa).profile.update!(permissions: %w[view_portfolio handle_data_subject_rights change_settings])
    entrar(user)

    get data_retention_path

    assert_response :success
    assert_select "h2#prazo", text: /Prazo de guarda vigente/
    assert_select "section[aria-labelledby=prazo] li", text: /Escola Alfa: 5 anos/
    assert_select "section[aria-labelledby=prazo] li a", text: "Alterar nos dados do credor"
    assert_select "section[aria-labelledby=previstos] th", text: /Maria Souza/
    assert_select "section[aria-labelledby=retidos] td", text: /ação judicial nº 77/
    assert_select "section[aria-labelledby=execucoes] td", text: /Concluída/
    assert_no_match(/Clínica Beta|StatementInvalid/, response.body)
    assert_select "#guarda[hx-trigger*='cable:retention-changed']"
    assert_select "meta[name=cable-channels]" do |meta|
      assert_includes meta.first["content"], "RetentionChannel"
    end
  end

  test "R138 (revisão 3): quem tem a 13 mas não a 4 vê a frase em vez do link para o prazo" do
    user = make_user(@alfa, %w[handle_data_subject_rights])
    entrar(user)

    get data_retention_path

    assert_select "section[aria-labelledby=prazo]", text: /O prazo é definido nos dados do credor/
    assert_select "section[aria-labelledby=prazo] a", 0
  end

  test "R140: quem não tem a 13 não vê o item do menu nem a página de guarda" do
    entrar(make_user(@alfa, []))

    get data_retention_path
    assert_response :not_found
    get root_path
    assert_select "nav a", text: "Guarda de dados", count: 0
  end

  test "R138: reter pela página some da previsão e aparece nos retidos; desfazer volta; o pedido do htmx traz só o trecho" do
    @maria.bill.update!(paid_on: Date.current - 5.years + 10.days)
    @maria.payment.update!(paid_on: Date.current - 5.years + 10.days)
    entrar(users(:joana))

    post customer_retention_path(@maria), params: { retention: { reason: "ação judicial" } }, headers: { "HTTP_REFERER" => data_retention_url }
    assert_redirected_to data_retention_url
    follow_redirect!
    assert_select "section[aria-labelledby=previstos] th", text: /Maria Souza/, count: 0
    assert_select "section[aria-labelledby=retidos] th", text: /Maria Souza/

    delete customer_retention_path(@maria), params: { retention: { reason: "encerrado" } }, headers: { "HTTP_REFERER" => data_retention_url }
    get data_retention_path, headers: htmx
    assert_select "section[aria-labelledby=previstos] th", text: /Maria Souza/
    assert_no_match(/<html/, response.body)
  end

  test "R138: retenção exige motivo, e reter anonimizado é recusado" do
    entrar(users(:joana))
    post customer_retention_path(@maria), params: { retention: { reason: "" } }
    assert_not @maria.reload.retained?
    Titular::Anonymizer.on_request(@maria, actor: users(:joana), reason: "pedido", document: @maria.document)
    post customer_retention_path(@maria), params: { retention: { reason: "tarde" } }
    assert_not @maria.reload.retained?
  end

  test "V10: a página de guarda não lista cliente de outro credor, nem o filtro por credor alcança credor sem a 13" do
    @beta_maria.bill.update!(paid_on: Date.current - 6.years)
    @beta_maria.payment.update!(paid_on: Date.current - 6.years)
    user = marta
    user.memberships.find_by!(tenant: @alfa).profile.update!(permissions: %w[view_portfolio handle_data_subject_rights])
    entrar(user)

    get data_retention_path(tenant: @beta.id)

    assert_select "section[aria-labelledby=previstos] th", text: /Maria Souza/, count: 0
  end

  test "R136: o prazo de guarda é salvo com a 4 no credor, com histórico; valor inválido e credor sem a 4 são recusados" do
    entrar(users(:joana))
    patch settings_retention_period_path, params: { tenant_id: @alfa.id, retention: { years: "7" } }
    assert_redirected_to settings_tenant_registry_path
    assert_equal 7, @alfa.setting.reload.retention_years
    assert_equal [ "5", "7" ], Change.find_by!(subject_type: "settings", event: "retention_years_changed").slice(:before, :after).values

    patch settings_retention_period_path, params: { tenant_id: @alfa.id, retention: { years: "0" } }
    assert_equal 7, @alfa.setting.reload.retention_years

    delete session_path
    entrar(marta)
    patch settings_retention_period_path, params: { tenant_id: @beta.id, retention: { years: "9" } }
    assert_response :not_found
    assert_equal 5, @beta.setting.reload.retention_years
    get settings_tenant_registry_path
    assert_select "form[action='#{settings_retention_period_path}']", 1
  end

  # ---- Estorno de título de cliente anonimizado (03, revisão 5; 07, revisão 5) ----

  test "estorno é recusado quando todos os clientes do contrato estão anonimizados, e segue havendo um identificável" do
    Titular::Anonymizer.on_request(@maria, actor: users(:joana), reason: "pedido", document: @maria.document)
    import = run_payments_import([ reversal_line("identificador_pagamento" => @maria.payment.identifier, "valor" => "10,00") ], kind: "reversals")
    assert_equal [ "título de cliente anonimizado" ], import.rejections.pluck(:reason)

    Import.update_all(status: "discarded")
    pedro = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro", code: "CT-8")
    ContractCustomer.find_or_create_by!(contract: pedro.contracts.first, customer: @maria)
    import = run_payments_import([ reversal_line("identificador_pagamento" => pedro.payment.identifier, "identificador_estorno" => "E2", "valor" => "10,00") ], kind: "reversals")
    assert_empty import.rejections
  end
end
