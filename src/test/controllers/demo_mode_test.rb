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

  test "a faixa avisa que os dados são fictícios e a tela de entrada lista os usuários públicos" do
    get new_session_path
    assert_select "aside.demonstracao", /fictícios e recriados todo dia às 04:00/
    assert_select "code", text: Demo.email("gestor")
    assert_select "code", text: Demo.password("operador")
    Rails.configuration.x.demo.enabled = false
    get new_session_path
    assert_select "aside.demonstracao", count: 0
  end

  test "a faixa aparece nas telas e a troca de senha some do menu do usuário" do
    entrar(users(:joana))
    get root_path
    assert_select "aside.demonstracao"
    assert_select "a", text: "Trocar a senha", count: 0
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

    get edit_password_path
    assert_redirected_to root_path
    patch password_path, params: { password: { current_password: "senha-de-teste-1", password: "uma-senha-nova-bem-longa", password_confirmation: "uma-senha-nova-bem-longa" } }
    assert_redirected_to root_path
    assert users(:joana).reload.authenticate("senha-de-teste-1"), "a senha não mudou"

    post settings_payment_accounts_path, params: { payment_account: { tenant_id: @alfa.id, modality: "boleto", provider: "fake", nickname: "x" } }
    assert_redirected_to root_path
    assert_equal 0, PaymentAccount.count

    patch settings_tenant_registry_path, params: { tenant: { legal_name: "Outro nome" } }
    assert_redirected_to root_path
  end

  test "a lista de contas de pagamento continua aberta para leitura" do
    entrar(users(:joana))
    get settings_payment_accounts_path
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
      file.truncate(Portfolio::CsvFile::MAX_BYTES + 1)
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
    assert_equal "canal;identificador;documento;titulo;data_pagamento;valor;meio", rows.first
    assert(rows.any? { |row| row.include?(";NF-77;") && row.start_with?(channel.code) })
    assert(rows.any? { |row| row.include?("NF-9999/1") }, "uma linha de título que não existe")
    File.delete(path)
    assert_equal 1, File.readlines(Demo::Files.reversals(@alfa).tap { |p| @reversal_path = p }).size
    File.delete(@reversal_path)
    assert bill
  end

  test "fora da demonstração nada é fechado nem trocado" do
    Rails.configuration.x.demo.enabled = false
    entrar(users(:joana))
    get edit_password_path
    assert_response :success
    assert_select "aside.demonstracao", count: 0
  end
end
