require "application_system_test_case"

# Cadastro do cliente e do credor no navegador (06): ficha com os contatos e as ações de edição (na SPA, fase 3: telefone e e-mail na célula, endereço no detalhe
# da linha, nome em "Dados do cliente"; design system, 7.1), dados do credor, política tela × carga e a conferência da carga com os avisos de contato.
class RegistryScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include SpaTestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321", origin: "load", seen_in_import_at: 2.days.ago)
    add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20), kept_by_tenant: true)
    add_contact(@maria, "email", "maria@exemplo.com.br", status: "invalid", reason: "caixa cheia")
    add_address(@maria, { street: "Rua das Flores", number: "120", complement: "ap 3", district: "Centro", city: "São Paulo", state: "SP", zip: "01001-000" })
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva Souza")
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def abrir_contatos
    entrar_na_casca
    abrir_ficha(@maria, aba: "contatos")
  end

  test "a aba Contatos mostra todos os contatos, um por linha, e o histórico do cadastro" do
    abrir_contatos
    na_aba_interna do
      assert_selector ".datagrid-view2 tr.datagrid-row", count: 4
      assert_selector ".datagrid-row", text: "Rua das Flores, 120"
      assert_selector ".datagrid-row .situacao", text: "Não perturbe"
    end
    aba_interna "Histórico"
    na_aba_interna { assert_selector "#historico-do-cadastro .datagrid-row", text: "Maria da Silva Souza" }
  end

  test "corrigir um telefone na célula: Esc desiste, o erro fica junto ao campo, Enter grava; o antigo fica inválido e o novo nasce válido" do
    contato = @maria.contacts.find_by!(key: "11987654321")
    abrir_contatos
    menu_da_linha("(11) 98765-4321", "Editar")
    # Edição na própria célula: sem diálogo nem formulário aberto antes do pedido.
    assert_no_selector ".dialogo-conteudo"
    campo = find("form.inline-editando input")
    campo.fill_in(with: "(11) 1111-1111")
    campo.send_keys(:escape)
    assert_no_selector "form.inline-editando"
    assert_equal "valid", contato.reload.status

    menu_da_linha("(11) 98765-4321", "Editar")
    find("form.inline-editando input").fill_in(with: "123")
    find("form.inline-editando input").send_keys(:enter)
    assert_selector "form.inline-editando .inline-erro", text: /telefone/i
    assert_equal "123", find("form.inline-editando input").value

    find("form.inline-editando input").fill_in(with: "(11) 98765-4312")
    find("form.inline-editando input").send_keys(:enter)
    assert_aviso "Contato corrigido"
    na_aba_interna { assert_selector ".datagrid-row", text: "(11) 98765-4312" }
    assert_equal [ "invalid", "valid" ], [ @maria.contacts.find_by!(key: "11987654321").status, @maria.contacts.find_by!(key: "11987654312").status ]
  end

  test "corrigir o endereço no detalhe da própria linha; Cancelar devolve o detalhe" do
    abrir_contatos
    menu_da_linha("Rua das Flores", "Editar")
    within(".datagrid-row-detail form.dialogo") do
      assert_field "Logradouro", with: "Rua das Flores"
      click_button "Cancelar"
    end
    assert_no_selector ".datagrid-row-detail form"

    menu_da_linha("Rua das Flores", "Editar")
    within(".datagrid-row-detail form.dialogo") do
      fill_in "Logradouro", with: "Rua das Acácias"
      click_button "Salvar contato"
    end
    assert_aviso "Contato corrigido"
    na_aba_interna { assert_selector ".datagrid-row", text: "Rua das Acácias, 120" }
    assert @maria.contacts.address.where(status: "valid").any? { |contato| contato.street == "Rua das Acácias" }
  end

  test "corrigir o nome em Dados do cliente: a aba se refaz com o nome novo no título" do
    entrar_na_casca
    abrir_ficha(@maria)
    within(".ficha-lateral") { click_button "Editar" }
    find("form.inline-editando input").fill_in(with: "Maria Souza Lima")
    click_button "Salvar"
    assert_aviso "Nome corrigido"
    assert_selector "#abas .tabs-selected .tabs-title", text: "Maria Souza Lima"
    assert_selector ".aba-raiz .cabecalho-da-pagina h1", text: "Maria Souza Lima"
    assert_selector ".ficha-lateral .nota", text: "mantido pelo credor"
    assert_equal "Maria Souza Lima", @maria.reload.name
  end

  test "marcar não perturbe pelo menu da linha, no diálogo" do
    contact = @maria.contacts.find_by!(key: "11987654321")
    abrir_contatos
    menu_da_linha("(11) 98765-4321", "Marcar como não perturbe")
    gravar_dialogo "Marcar como não perturbe"
    assert_aviso "Situação do contato alterada"
    assert_equal "do_not_disturb", contact.reload.status
  end

  # Na SPA (fase 7): a recusa refaz a tela com o que foi digitado; o axe saiu da área interna (plano, D7).
  test "dados do credor, a política tela × carga e os resultados, nas abas" do
    entrar_na_casca
    visit settings_tenant_registry_path
    assert_selector ".aba-raiz h1", text: "Dados do credor", wait: 15
    sem_rolagem_horizontal
    within(find(".aba-raiz section.cartao", text: "Escola Alfa", match: :first)) do
      fill_in "CNPJ", with: "11.111.111/1111-11"
      fill_in "Razão social", with: "Comércio Exemplo Ltda"
      click_button "Salvar dados do credor"
    end
    assert_selector ".aba-raiz .aviso", text: "CNPJ inválido", wait: 10
    assert_field "Razão social", with: "Comércio Exemplo Ltda"

    abrir_aba settings_portfolio_path
    assert_selector ".aba-raiz", text: "Correção na tela ou carga: qual vale", wait: 10
    abrir_aba settings_contact_results_path
    assert_selector ".aba-raiz h1", text: "Resultados de acionamento", wait: 10
    menu_da_linha("Número ou endereço inexistente", "Editar")
    no_dialogo { assert_checked_field "Invalida o contato" }
  end

  test "a conferência da carga com avisos de contato e dados mantidos pelo credor" do
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "c.csv",
      file: write_csv([ { "documento" => PaymentsHelper::MARIA, "nome" => "Maria da Silva", "titulo" => "NF-9", "vencimento" => "10/09/2026", "valor" => "10,00", "telefone" => "(11) 3333-4444",
                         "telefone2" => "123", "contrato" => "CT-1" } ], header: %w[documento nome titulo vencimento valor telefone telefone2 contrato]))
    perform_enqueued_jobs(only: CheckImportJob)

    entrar_na_casca
    visit import_path(import) # na SPA desde a fase 5
    assert_selector ".aba-raiz #contatos-da-conferencia", wait: 15
    assert_selector ".aba-raiz #mantidos-pelo-credor"
    sem_rolagem_horizontal
  end

  test "o formulário de acionamento oferece os contatos do canal e o campo de salvar contato" do
    entrar_na_casca
    abrir_ficha(@maria)
    click_link "Registrar acionamento"
    no_dialogo do
      escolher "Canal", "WhatsApp"
      assert_selector "datalist option[value='(11) 98765-4321']", visible: :all
      assert_no_selector "datalist option[value='maria@exemplo.com.br']", visible: :all
      assert_field "Salvar este contato no cadastro", type: :checkbox
    end
  end
end
