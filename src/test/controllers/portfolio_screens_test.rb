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

  test "sem sessão, o endereço leva à casca, e o trecho recebe 401" do
    get summary_path
    assert_redirected_to "/#/resumo"
    get summary_path, headers: TRECHO
    assert_response :unauthorized
  end

  test "o resumo, a lista e a ficha respondem para quem consulta a carteira" do
    entrar(@joana)
    get summary_path, headers: TRECHO
    assert_response :success
    assert_select "h1", "Resumo da carteira"
    get customers_path, headers: TRECHO
    assert_response :success
    assert_select ".lista h1", "Clientes"
    assert_equal 200, response.status
    get_clientes
    assert_response :success
    get_ficha(@cliente)
    assert_response :success
    assert_select "h1", "Maria Souza"
  end

  test "o resumo é um conjunto só de totais, com o filtro de credor e as tabelas por faixa sempre (01, revisão 8)" do
    entrar(users(:ana))
    tenants(:beta).setting.update!(aging_brackets: [ { from: 1, to: 60 }, { from: 61, to: nil } ])
    get summary_path, headers: TRECHO
    assert_select "h2", text: /Escola Alfa|Clínica Beta/, count: 0
    assert_select "dl.kpis dt", text: /Clientes em cobrança/
    assert_select "select[name=credor] option", text: "Todos os credores"
    assert_select "select[name=credor] option", text: "Clínica Beta"
    assert_select "h2", text: /Faixas de atraso — /, count: 2 # faixas diferentes: as duas tabelas, nas faixas padrão
    assert_select "p", text: /Faixas padrão do sistema/
    assert_select "td", text: "181–360"

    # O filtro refaz só o trecho, com as faixas do credor escolhido.
    get summary_path(credor: tenants(:beta).id), headers: TRECHO.merge("X-CRM-Fragmento" => "1")
    assert_select "form.filtros", count: 0
    assert_select "#resultado h2", text: /Faixas de atraso — /, count: 2
    assert_select "td", text: "1–60"
    assert_select "p", text: /Faixas padrão do sistema/, count: 0
  end

  test "quem consulta um credor só não vê o filtro de credor no resumo" do
    entrar(@joana)
    get summary_path, headers: TRECHO
    assert_select "select[name=credor]", count: 0
    assert_select "h2", text: /Faixas de atraso — /, count: 2
    assert_select "p", text: /Faixas padrão do sistema/, count: 0
  end

  test "a busca da lista devolve só a página da grade, em JSON" do
    entrar(@joana)
    corpo = get_clientes(busca: "maria")
    assert_response :success
    assert_equal [ "Maria Souza" ], corpo["rows"].map { |linha| celula(linha, "name") }
    assert_equal 1, corpo["total"]
  end

  test "ficha de cliente de outro credor responde como não encontrada" do
    entrar(@joana)
    get_ficha(@beta_cliente)
    assert_response :not_found
  end

  test "o envio de uma planilha cria a importação e enfileira a conferência" do
    entrar(@joana)
    get new_import_path, headers: TRECHO
    assert_response :success
    arquivo = fixture_file_upload(write_csv([ csv_line ]), "text/csv")
    assert_enqueued_with(job: CheckImportJob) do
      post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental", file: arquivo } }
    end
    assert_redirected_to import_path(Import.last)
    get import_path(Import.last), headers: TRECHO
    assert_response :success
    assert_select "h1", /Importação de/

    # Na SPA, o envio termina no `X-CRM-Evento`, e a importação abre na aba dela.
    Import.last.update!(status: "discarded")
    post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental", file: fixture_file_upload(write_csv([ csv_line ]), "text/csv") } }, headers: TRECHO
    assert_response :no_content
    assert_equal import_path(Import.last), evento_da_spa["navegar"]
  end

  test "envio sem arquivo mostra o erro" do
    entrar(@joana)
    post imports_path, params: { import: { tenant_id: @alfa.id, mode: "incremental" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Escolha o arquivo/
  end

  test "operador não envia nem confirma importação" do
    entrar(users(:carlos))
    get new_import_path, headers: TRECHO
    assert_response :not_found
    get imports_path, headers: TRECHO
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
    patch settings_portfolio_path, params: { credor: @alfa.id, section: "brackets", brackets: [ { from: "1", to: "60" }, { from: "61", to: "" } ] }
    assert_redirected_to settings_portfolio_path
    assert_equal 2, @alfa.reload.setting.aging_brackets.size

    patch settings_portfolio_path, params: { credor: @alfa.id, section: "brackets", brackets: [ { from: "1", to: "10" }, { from: "30", to: "" } ] }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /buraco/i
    # A recusa devolve as linhas como foram digitadas, mais uma em branco, e a prévia delas.
    assert_select "input[name='brackets[][from]'][value='30']"
    assert_select "[data-previa-das-faixas] li", text: "mais de 29 dias"

    onze = (1..11).map { |n| { from: (n * 10 - 9).to_s, to: (n == 11 ? "" : (n * 10).to_s) } }
    patch settings_portfolio_path, params: { credor: @alfa.id, section: "brackets", brackets: onze }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /no máximo 10 faixas/i
  end

  test "a tela das faixas tem uma linha em branco, Criar faixa e Excluir em cada linha (T6)" do
    entrar(@joana)
    get settings_portfolio_path, headers: TRECHO
    bloco = css_select("[data-faixas]").first
    assert_equal 7, bloco.css("tbody > tr").size # as 6 faixas padrão e uma em branco
    assert_equal 1, bloco.css("tbody > tr").count { |linha| linha.css("input").all? { |campo| campo["value"].blank? } }
    assert_equal 7, bloco.css("tbody [data-excluir-faixa]").size
    assert_select "[data-faixas] button[data-criar-faixa]", text: "Criar faixa"
    assert_select "[data-faixas] template[data-modelo-da-faixa]"
    assert_select "input[name='brackets[][remove]']", count: 0
  end

  test "operador não abre a configuração" do
    entrar(users(:carlos))
    get settings_portfolio_path, headers: TRECHO
    assert_response :not_found
  end
end
