require "test_helper"

# O modo de demonstração pelo caminho do usuário (CRM_DEMO=1): faixa de aviso, telas fechadas, texto trocado, arquivo descartado.
class DemoModeTest < ActionDispatch::IntegrationTest
  setup do
    @previous = Rails.configuration.x.demo.enabled
    Rails.configuration.x.demo.enabled = true
    @alfa = tenants(:alfa)
  end

  teardown { Rails.configuration.x.demo.enabled = @previous }

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "a faixa da casca avisa que os dados são fictícios e a entrada lista os usuários públicos" do
    get root_path
    assert_select ".faixa", /fictícios e recriados todo dia às 04:00/
    assert_select ".entrada-demonstracao code", text: Demo.email("gestor")
    assert_select ".entrada-demonstracao code", text: Demo.password("operador")
    Rails.configuration.x.demo.enabled = false
    get root_path
    assert_select ".faixa", count: 0
  end

  test "a troca de senha some do menu do usuário" do
    entrar(users(:joana))
    get menu_path(format: :json)
    assert_equal false, response.parsed_body["trocar_senha"]
  end

  test "usuários, perfis, senha e contas de pagamento recusam alteração com a mensagem da demonstração" do
    entrar(users(:joana))
    post memberships_path, params: { membership: { tenant_id: @alfa.id, email_address: "novo@exemplo.com.br", name: "Novo", profile_id: 1 } }
    assert_redirected_to root_path
    assert_equal Demo::Restrictions::MESSAGE, flash[:alert]
    assert_not User.exists?(email_address: "novo@exemplo.com.br")

    post profiles_path, params: { profile: { tenant_id: @alfa.id, name: "Perfil novo", permissions: [ "view_portfolio" ] } }
    assert_redirected_to root_path
    assert_not Profile.exists?(name: "Perfil novo")

    get edit_password_path, headers: TRECHO
    assert_select "h1", "Fechado na demonstração"
    patch password_path, params: { password: { current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa" } }
    assert_redirected_to root_path
    assert users(:joana).reload.authenticate("senha-de-teste-1"), "a senha não mudou"

    post settings_payment_accounts_path, params: { payment_account: { tenant_id: @alfa.id, modality: "boleto", provider: "fake", nickname: "x" } }
    assert_redirected_to root_path
    assert_equal 0, PaymentAccount.count

    patch settings_tenant_registry_path, params: { tenant: { legal_name: "Outro nome" } }
    assert_redirected_to root_path
  end

  # A SPA não segue o redirecionamento (fase 7): a recusa chega como ela entende.
  test "na SPA, a recusa da demonstração vem como fim de ação, junto do campo na edição na linha e no lugar da tela que só serve para alterar" do
    entrar(users(:joana))
    post profiles_path, params: { profile: { tenant_id: @alfa.id, name: "Perfil novo", permissions: [ "view_portfolio" ] } }, headers: TRECHO
    assert_response :no_content
    assert_equal [ Demo::Restrictions::MESSAGE, "danger" ], evento_da_spa.values_at("aviso", "tom")
    assert_not Profile.exists?(name: "Perfil novo")

    patch membership_profile_path(memberships(:carlos_alfa)), params: { membership: { profile_id: profiles(:alfa_manager).id } }, headers: TRECHO.merge("X-CRM-Inline" => "1")
    assert_response :unprocessable_content
    assert_equal Demo::Restrictions::MESSAGE, response.parsed_body["erro"]
    assert_equal profiles(:alfa_operator), memberships(:carlos_alfa).reload.profile

    get new_settings_payment_account_path, headers: TRECHO
    assert_response :success
    assert_select "h1", "Fechado na demonstração"
    assert_select "aside", text: Demo::Restrictions::MESSAGE
  end

  test "a lista dos métodos de recebimento, com as integrações, continua aberta para leitura (16, R373)" do
    entrar(users(:joana))
    get settings_channels_path, headers: TRECHO
    assert_response :success
  end

  test "o texto e o contato digitados no acionamento são trocados por texto fictício" do
    customer = make_customer(@alfa)
    entrar(users(:joana))
    result = result_of(@alfa, :no_answer)
    post customer_contact_attempts_path(customer), params: { contact_attempt: { channel: "phone", result_id: result.id, text: "Ligar para a irmã Maria, CPF 123.456.789-00", contact_used: "(11) 98765-4321" } }
    attempt = ContactAttempt.where(customer_id: customer.id).last
    assert_equal Demo::Restrictions::TEXT, attempt.text
    assert_equal Demo::Restrictions::CONTACT, attempt.contact_used
  end

  test "o arquivo enviado é descartado sem ser lido e trocado por um arquivo fictício" do
    entrar(users(:joana))
    Tempfile.create([ "carteira", ".csv" ]) do |file|
      file.write("documento;nome;titulo;vencimento;valor\n529.982.247-25;SEGREDO-DO-VISITANTE;NF-1;10/09/2026;10,00\n")
      file.flush
      assert_difference -> { Import.count }, 1 do
        post imports_path, params: { import: { tenant_id: @alfa.id, kind: "portfolio", mode: "incremental", file: Rack::Test::UploadedFile.new(file.path, "text/csv") } }
      end
    end
    import = Import.order(:id).last
    assert_equal Demo::Files::NAME, import.original_name
    content = File.read(import.file_path)
    assert_not_includes content, "SEGREDO-DO-VISITANTE"
    assert_operator content.lines.size, :>=, 400
    assert_empty Dir[Rails.root.join("tmp", "*-demo-*.csv")], "o arquivo temporário foi apagado"
  end

  test "o limite de 50 MB continua valendo na demonstração, sem ler o arquivo" do
    entrar(users(:joana))
    Tempfile.create([ "grande", ".csv" ]) do |file|
      file.truncate(Ingestion::CsvReader::MAX_BYTES + 1)
      assert_no_difference -> { Import.count } do
        post imports_path, params: { import: { tenant_id: @alfa.id, kind: "portfolio", mode: "incremental", file: Rack::Test::UploadedFile.new(file.path, "text/csv") } }
      end
    end
    assert_response :unprocessable_content
    assert_select "aside.aviso", text: /acima do limite de 50 MB/
  end

  test "os arquivos fictícios de pagamentos e estornos saem dos títulos e pagamentos do credor" do
    channel = make_channel(@alfa)
    bill = make_bill(@alfa, number: "NF-77", amount_cents: 50_000)
    path = Demo::Files.for("payments", @alfa)
    rows = File.readlines(path, chomp: true)
    assert_equal "metodo_recebimento;identificador;documento;titulo;data_pagamento;valor;meio", rows.first
    assert(rows.any? { |row| row.include?(";NF-77;") && row.start_with?(channel.code) })
    assert(rows.any? { |row| row.include?("NF-9999/1") }, "uma linha de título que não existe")
    File.delete(path)
    assert_equal 1, File.readlines(Demo::Files.reversals(@alfa).tap { |p| @reversal_path = p }).size
    File.delete(@reversal_path)
    assert bill
  end

  test "com mais de um sistema, os arquivos fictícios trazem os ids e a coluna sistema, e passam na conferência (17)" do
    make_channel(@alfa)
    make_bill(@alfa, number: "NF-77", amount_cents: 50_000)
    joana = users(:joana)
    erp = SourceSystems::Manager.new(joana).create(tenant: @alfa, name: "ERP Acadêmico", key_kind: "own_id")
    service = Portfolio::ImportService.new

    # A carteira do sistema de id próprio: os ids em cada linha, nenhuma recusa, e os clientes ficam com a identidade do sistema.
    path = Demo::Files.for("portfolio", @alfa, erp)
    assert_equal Demo::PortfolioSheet::REMOTE_HEADER.join(";"), File.open(path, &:readline).chomp
    import = service.start(tenant: @alfa, user: joana, file: path, mode: :incremental, source_system: erp)
    File.delete(path)
    import.checker.run(import)
    assert_equal 0, ImportRejection.where(import_id: import.id).count
    import.reload.confirmer.run(import)
    assert_predicate import.reload, :confirmed?
    assert_equal 60, CustomerIdentity.where(tenant_id: @alfa.id, source_system_id: erp.id).count
    assert_equal 0, Bill.where(tenant_id: @alfa.id, source_system_id: erp.id, external_id: nil).count

    # Os pagamentos: cada linha diz o sistema do título, e a do sistema de id próprio leva o id.
    path = Demo::Files.for("payments", @alfa)
    rows = File.readlines(path, chomp: true)
    assert_equal "metodo_recebimento;identificador;documento;titulo;data_pagamento;valor;meio;sistema;id_titulo", rows.first
    assert(rows.any? { |row| row.include?(";NF-77;") && row.end_with?(";Planilha;") })
    assert(rows.any? { |row| row.match?(/;ERP Acadêmico;LAN-\d+-\d\z/) })
    import = service.start(tenant: @alfa, user: joana, file: path, mode: :incremental, kind: "payments")
    File.delete(path)
    import.checker.run(import)
    assert_equal 0, ImportRejection.where(import_id: import.id).count
    assert_not import.reload.rejected?
  end

  test "fora da demonstração nada é fechado nem trocado" do
    Rails.configuration.x.demo.enabled = false
    entrar(users(:joana))
    get edit_password_path, headers: TRECHO
    assert_response :success
    assert_select "aside.demonstracao", count: 0
  end
end
