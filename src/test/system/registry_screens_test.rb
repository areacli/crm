require "application_system_test_case"

# Cadastro do cliente e do credor no navegador (06): ficha com os contatos e as ações de edição, dados do credor, política tela × carga e a
# conferência da carga com os avisos de contato, todos no axe, sem rolagem horizontal.
class RegistryScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321", origin: "load", seen_in_import_at: 2.days.ago)
    add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20), kept_by_tenant: true)
    add_contact(@maria, "email", "maria@exemplo.com.br", status: "invalid", reason: "caixa cheia")
    add_address(@maria, { street: "Rua das Flores", number: "120", complement: "ap 3", district: "Centro", city: "São Paulo", state: "SP", zip: "01001-000" })
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva Souza")
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def abrir_tudo = page.execute_script("document.querySelectorAll('main details').forEach((d) => d.open = true)")

  test "a ficha com os contatos, as ações de edição abertas e o histórico passa no axe" do
    visit customer_path(@maria)
    assert_selector "h2", text: "Contatos"
    assert_selector "#contatos ul.contatos li", count: 2
    abrir_tudo
    assert_selector "#todos-os-contatos tbody tr[id^=contato-]", count: 4
    assert_selector "#historico-do-cadastro li"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "corrigir um contato pela ficha: o antigo fica inválido, o novo nasce válido e a tela mostra o aviso" do
    visit customer_path(@maria)
    find("#todos-os-contatos > summary").click
    within("#editar-contato-#{@maria.contacts.find_by!(key: '11987654321').id}") do
      find("summary", text: "Editar").click
      fill_in "Telefone", with: "(11) 98765-4312"
      click_button "Corrigir contato"
    end

    assert_text "Contato corrigido"
    assert_equal [ "invalid", "valid" ], [ @maria.contacts.find_by!(key: "11987654321").status, @maria.contacts.find_by!(key: "11987654312").status ]
  end

  test "marcar não perturbe e voltar a válido pela ficha" do
    contact = @maria.contacts.find_by!(key: "11987654321")
    visit customer_path(@maria)
    find("#todos-os-contatos > summary").click
    within("#editar-contato-#{contact.id}") do
      find("summary", text: "Editar").click
      click_button "Marcar não perturbe"
    end
    assert_text "Situação do contato alterada"
    assert_equal "do_not_disturb", contact.reload.status
  end

  test "dados do credor, a política tela × carga e os resultados passam no axe" do
    visit settings_tenant_registry_path
    assert_selector "h1", text: "Dados do credor"
    assert_acessivel
    sem_rolagem_horizontal
    fill_in "CNPJ", with: "11.111.111/1111-11"
    fill_in "Razão social", with: "Comércio Exemplo Ltda"
    click_button "Salvar dados do credor"
    assert_text "CNPJ inválido"
    assert_acessivel

    visit settings_portfolio_path
    assert_text "Correção na tela ou carga: qual vale"
    assert_acessivel
    visit edit_settings_contact_result_path(result_of(@alfa, :wrong_number))
    assert_checked_field "Invalida o contato"
    assert_acessivel
  end

  test "a conferência da carga com avisos de contato e dados mantidos pelo credor passa no axe" do
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "c.csv",
      file: write_csv([ { "documento" => PaymentsHelper::MARIA, "nome" => "Maria da Silva", "titulo" => "NF-9", "vencimento" => "10/09/2026", "valor" => "10,00", "telefone" => "(11) 3333-4444",
                         "telefone2" => "123", "contrato" => "CT-1" } ], header: %w[documento nome titulo vencimento valor telefone telefone2 contrato]))
    perform_enqueued_jobs(only: CheckImportJob)

    visit import_path(import)
    assert_selector "#contatos-da-conferencia"
    assert_selector "#mantidos-pelo-credor"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "o formulário de acionamento oferece os contatos do canal e o campo de salvar contato passa no axe" do
    visit customer_path(@maria)
    select "WhatsApp", from: "Canal"
    assert_selector "datalist#contatos-do-cliente option[value='(11) 98765-4321']", visible: :all
    assert_no_selector "datalist#contatos-do-cliente option[value='maria@exemplo.com.br']", visible: :all
    assert_field "Salvar este contato no cadastro", type: :checkbox
    assert_acessivel
  end
end
