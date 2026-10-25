require "test_helper"

# Telas da carteira: acesso por permissão e escopo por credor.
class PortfolioScreensTest < ActionDispatch::IntegrationTest
  include CsvHelper
  include ActiveJob::TestHelper

  setup do
    @joana = users(:joana)
    @alfa = tenants(:alfa)
    @cliente = Customer.create!(tenant: @alfa, document: "52998224725", name: "Maria Souza")
    contrato = Contract.create!(tenant: @alfa, code: "C-1")
    Bill.create!(tenant: @alfa, contract: contrato, customer: @cliente, number: "T1", due_date: Date.current - 40, amount_cents: 10_000)
    @beta_cliente = Customer.create!(tenant: tenants(:beta), document: "11144477735", name: "Cliente do Beta")
  end

  def entrar(usuario, senha = "senha-de-teste-1")
    post session_path, params: { email_address: usuario.email_address, password: senha }
  end

  test "sem sessão, vai para a entrada" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "o resumo, a lista e a ficha respondem para quem consulta a carteira" do
    entrar(@joana)
    get root_path
    assert_response :success
    assert_select "h1", "Resumo da carteira"
    get customers_path
    assert_response :success
    assert_select "th a", text: "Cliente"
    get customer_path(@cliente)
    assert_response :success
    assert_select "h1", "Maria Souza"
  end

  test "o resumo é um conjunto só de totais: sem nome de credor e, com faixas diferentes, só a nota das faixas (25/10/2026)" do
    entrar(users(:ana))
    get root_path
    assert_select "h2", text: /Escola Alfa|Clínica Beta/, count: 0
    assert_select "section h2", text: "Carteira", count: 1
    assert_select "h2", text: /Faixas de atraso — /, count: 2 # faixas iguais: duas tabelas, somadas
    tenants(:beta).setting.update!(aging_brackets: [ { from: 1, to: 60 }, { from: 61, to: nil } ])
    get root_path
    assert_select "section h2", text: "Faixas de atraso", count: 1
    assert_select "p", text: /diferem entre os credores/
    assert_select "table caption", text: /Faixas/, count: 0
  end

  test "a busca pelo htmx devolve só o trecho" do
    entrar(@joana)
    get customers_path(q: "maria"), headers: { "HX-Request" => "true" }
    assert_response :success
    assert_select "#resultado"
    assert_select "header", false
  end

  test "ficha de cliente de outro credor responde como não encontrada" do
    entrar(@joana)
    get customer_path(@beta_cliente)
    assert_response :not_found
  end

  test "o envio de uma planilha cria a importação e enfileira a conferência" do
    entrar(@joana)
    get new_import_path
    assert_response :success
    arquivo = fixture_file_upload(write_csv([ csv_line ]), "text/csv")
    assert_enqueued_with(job: CheckImportJob) do
      post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental", file: arquivo } }
    end
    assert_redirected_to import_path(Import.last)
    follow_redirect!
    assert_response :success
    assert_select "h1", /Importação de/
  end

  test "envio sem arquivo mostra o erro" do
    entrar(@joana)
    post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Escolha o arquivo/
  end

  test "operador não envia nem confirma importação" do
    entrar(users(:carlos))
    get new_import_path
    assert_response :not_found
    get imports_path
    assert_response :not_found
  end

  test "a planilha modelo é baixada" do
    entrar(@joana)
    get template_imports_path
    assert_response :success
    assert_match "documento;nome", response.body
  end

  test "a configuração troca as faixas e recusa faixas com buraco" do
    entrar(@joana)
    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "brackets", brackets: [ { from: "1", to: "60" }, { from: "61", to: "" } ] }
    assert_redirected_to settings_portfolio_path
    assert_equal 2, @alfa.reload.setting.aging_brackets.size

    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "brackets", brackets: [ { from: "1", to: "10" }, { from: "30", to: "" } ] }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /buraco/i
  end

  test "operador não abre a configuração" do
    entrar(users(:carlos))
    get settings_portfolio_path
    assert_response :not_found
  end
end
