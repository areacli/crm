require "test_helper"

# Telas do cadastro (06): ficha com os contatos (R124), edição pelo cliente (R113, R113a), dados do credor (R106), política tela × carga (R117),
# integração com o acionamento (R120 a R123) e isolamento por credor (V10).
class RegistryScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @maria = make_customer(@alfa)
    @beta_customer = make_customer(@beta, name: "Cliente da Beta")
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  # Marta da especificação: edita o cadastro na Alfa e só consulta na Beta.
  def marta
    user = make_user(@alfa, %w[edit_customer_registry record_contact_attempts change_settings])
    Membership.create!(user: user, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio record_contact_attempts change_settings]))
    user
  end

  def use(customer, channel, text, at)
    ContactAttempt.create!(tenant_id: customer.tenant_id, customer: customer, user: users(:joana), result: result_of(customer.tenant, :no_answer), result_kind: "no_contact",
                           channel: channel, contact_used: text, contacted_at: at)
  end

  # ---- Ficha (R124) ----

  test "R124 (DC6): até três contatos válidos no topo, telefones primeiro e os usados mais recentemente antes; 'ver todos' traz todos com situação, origem e motivo" do
    a = add_contact(@maria, "phone", "(11) 91111-1111")
    b = add_contact(@maria, "phone", "(11) 92222-2222")
    c = add_contact(@maria, "phone", "(11) 93333-3333")
    add_contact(@maria, "email", "maria@exemplo.com.br")
    add_contact(@maria, "phone", "(11) 94444-4444", status: "invalid", reason: "número errado")
    add_contact(@maria, "phone", "(11) 95555-5555", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20))
    use(@maria, "phone", "(11) 93333-3333", 1.hour.ago)
    use(@maria, "whatsapp", "11 92222 2222", 5.hours.ago)
    entrar(users(:joana))

    get customer_path(@maria)

    assert_response :success
    assert_select "#contatos-resumo ul.contatos > li", 3
    assert_equal [ c.value, b.value, a.value ], css_select("#contatos-resumo ul.contatos > li").map { |li| li.text.sub(/\A\s*Telefone:\s*/, "").strip }
    assert_select "#contatos-resumo ul.contatos li", text: /maria@exemplo/, count: 0
    assert_select "#contatos-resumo a", text: /Ver todos e editar \(6\)/
    get customer_path(@maria, aba: "contatos")
    assert_select "#contatos tbody tr[id^=contato-]", 6
    assert_select "#contatos", text: /número errado/
    assert_select "#contatos", text: /pedido em 20\/10\/2026/
    assert_select "#contatos .situacao", text: "Não perturbe"
  end

  test "R124: a ficha mostra a origem e a data da carga em que o contato veio" do
    add_contact(@maria, "phone", "(11) 98765-4321", origin: "load", seen_in_import_at: Time.zone.local(2026, 10, 20, 9))
    entrar(users(:joana))

    get customer_path(@maria, aba: "contatos")

    assert_select "#contatos", text: /Carga.*veio na carga de 20\/10\/2026/m
  end

  test "R113 (critério de aceite): quem não tem 'editar cadastro' vê os contatos, mas nenhum botão de edição, e o envio direto é recusado e registrado" do
    contact = add_contact(@maria, "phone", "(11) 98765-4321")
    viewer = make_user(@alfa, [])
    entrar(viewer)

    get customer_path(@maria)
    assert_select "#contatos-resumo li", text: /98765-4321/
    assert_select "#contatos-resumo button", 0
    assert_select "a[hx-get*='/nome/'], a[hx-get*='/contatos/']", 0
    get customer_path(@maria, aba: "contatos")
    assert_select "#contatos button.menu-de-linha", 0
    get edit_customer_name_path(@maria), headers: painel
    assert_response :not_found

    patch customer_contact_path(@maria, contact), params: { contact: { value: "(11) 98765-4312" } }
    assert_response :not_found
    post customer_contacts_path(@maria), params: { contact: { kind: "phone", value: "(11) 97777-7777" } }
    assert_response :not_found
    patch customer_name_path(@maria), params: { customer: { name: "Outro" } }
    assert_response :not_found
    assert_equal "valid", contact.reload.status
    assert_equal [ 1, "Maria Souza" ], [ @maria.contacts.count, @maria.reload.name ]
    assert_equal @alfa.id, AccessEvent.where(event: "access_denied").last.tenant_id
  end

  test "R113 e R116: o operador acrescenta, corrige, marca inválido, não perturbe e volta a válido pela ficha, e o histórico mostra tudo com o nome dele" do
    entrar(users(:carlos))

    post customer_contacts_path(@maria), params: { contact: { kind: "phone", value: "(11) 98765-4321" } }
    assert_redirected_to customer_path(@maria, aba: "contatos")
    follow_redirect!
    assert_select "aside", text: /Contato criado/
    contact = @maria.contacts.sole

    patch customer_contact_path(@maria, contact), params: { contact: { value: "(11) 98765-4312" } }
    assert_equal [ "invalid", "corrigido para (11) 98765-4312" ], [ contact.reload.status, contact.reason ]
    fixed = @maria.contacts.find_by!(status: "valid")

    patch customer_contact_status_path(@maria, fixed), params: { status: { status: "do_not_disturb", requested_on: Date.current.iso8601 } }
    assert_equal "do_not_disturb", fixed.reload.status
    patch customer_contact_status_path(@maria, fixed), params: { status: { status: "valid", reason: "voltou a aceitar" } }
    patch customer_contact_status_path(@maria, fixed), params: { status: { status: "invalid", reason: "telefone desligado" } }
    assert_equal [ "invalid", "telefone desligado" ], [ fixed.reload.status, fixed.reason ]

    get customer_path(@maria, aba: "historico")
    assert_select "#historico-do-cadastro li", text: /Carlos Lima/, count: 6
    assert_select "#historico-do-cadastro li", text: /válido → não perturbe/
  end

  test "R113: corrigir o nome pela ficha marca 'mantido pelo credor'; o documento não tem campo de edição (R115)" do
    entrar(users(:carlos))

    get edit_customer_name_path(@maria), headers: painel
    assert_select "[data-painel] form.painel input[name='customer[name]']"
    assert_select "input[name*='document']", 0
    patch customer_name_path(@maria), params: { customer: { name: "Maria da Silva Souza" } }
    follow_redirect!

    assert_select "aside", text: /Nome corrigido/
    assert_select "section", text: /mantido pelo credor/
    assert_equal "Maria da Silva Souza", @maria.reload.name
  end

  test "R126 (DC5): criar na ficha um contato igual ao do credor avisa que ele entrou inválido" do
    @alfa.update!(phone: "(11) 3000-1000")
    entrar(users(:carlos))

    post customer_contacts_path(@maria), params: { contact: { kind: "phone", value: "11 3000-1000" } }
    follow_redirect!

    assert_select "aside", text: /Contato criado como inválido: é contato do credor/
    assert_equal "invalid", @maria.contacts.sole.status
  end

  test "regras recusadas voltam à ficha com a mensagem" do
    add_contact(@maria, "phone", "(11) 98765-4321")
    entrar(users(:carlos))

    post customer_contacts_path(@maria), params: { contact: { kind: "phone", value: "+55 11 98765-4321" } }
    follow_redirect!
    assert_select "aside", text: /Este contato já está cadastrado \(válido\)/
    post customer_contacts_path(@maria), params: { contact: { kind: "email", value: "sem-arroba" } }
    follow_redirect!
    assert_select "aside", text: /E-mail inválido/
    patch customer_contact_status_path(@maria, @maria.contacts.first), params: { status: { status: "invalid", reason: "" } }
    follow_redirect!
    assert_select "aside", text: /Informe o motivo/
  end

  test "R113a e R33 (critério de aceite): Marta corrige na Alfa e é recusada, com o credor registrado, na Beta, que mostra os contatos sem botões" do
    user = marta
    beta_contact = add_contact(@beta_customer, "phone", "(11) 98765-4321")
    alfa_contact = add_contact(@maria, "phone", "(11) 98765-4321")
    entrar(user)

    patch customer_contact_path(@maria, alfa_contact), params: { contact: { value: "(11) 98765-4312" } }
    assert_equal "invalid", alfa_contact.reload.status
    assert_equal user.id, Change.where(subject_type: "customer_contact", event: "corrected").last.user_id

    patch customer_contact_path(@beta_customer, beta_contact), params: { contact: { value: "(11) 98765-4312" } }
    assert_response :not_found
    assert_equal "valid", beta_contact.reload.status
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id

    get customer_path(@beta_customer, aba: "contatos")
    assert_select "#contatos tbody", text: /98765-4321/
    assert_select "#contatos button.menu-de-linha", 0
    get customer_path(@maria, aba: "contatos")
    assert_select "#contatos button.menu-de-linha", minimum: 1
  end

  test "V10, R108a (critério de aceite): os contatos de um credor não aparecem na ficha do outro, e quem não vê o credor recebe 404 por link direto" do
    add_contact(@maria, "phone", "(11) 98765-4321")
    only_beta = make_user(@beta, %w[edit_customer_registry])
    entrar(only_beta)

    get customer_path(@beta_customer)
    assert_response :success
    assert_select "#contatos", text: /98765-4321/, count: 0
    get customer_path(@maria)
    assert_response :not_found
    post customer_contacts_path(@maria), params: { contact: { kind: "phone", value: "(11) 97777-7777" } }
    assert_response :not_found
    assert_equal 1, @maria.contacts.count
  end

  test "R124a (critério de aceite): a ficha de Pedro mostra o contrato, o papel dele e o de Ana, sem botão para alterar contrato ou papéis" do
    ana = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Ana Prado", contract_code: "C-2026-7")
    pedro = make_customer(@alfa, document: "111.444.777-35", name: "Pedro Lima", contract_code: "C-2026-7")
    contract = Contract.find_by!(tenant: @alfa, code: "C-2026-7")
    ContractCustomer.where(contract: contract, customer: ana).update_all(roles: %w[holder financial_responsible])
    ContractCustomer.where(contract: contract, customer: pedro).update_all(roles: %w[holder])
    entrar(users(:joana))

    get customer_path(pedro)

    assert_select "#contratos tbody tr", 1
    assert_select "#contratos th", text: "C-2026-7"
    assert_select "#contratos td", text: /titular/
    assert_select "#contratos td", text: /Ana Prado\s*titular e responsável financeiro/
    assert_select "#contratos td", text: /Pedro Lima\s*titular/
    assert_select "#contratos button, #contratos form, #contratos input", 0
  end

  test "R124a: sem responsável declarado, os titulares aparecem como responsáveis financeiros (MT-16)" do
    ContractCustomer.update_all(roles: %w[holder])
    entrar(users(:joana))

    get customer_path(@maria)

    assert_select "#contratos td", text: /titular e responsável financeiro/
  end

  # ---- Acionamento (R120 a R123) ----

  # O aviso que o painel mostra ao terminar: vem no cabeçalho HX-Trigger.
  def notice_of_panel = JSON.parse(response.headers["HX-Trigger"]).dig("painel:concluido", "aviso").to_s

  test "R120 (critério de aceite): as sugestões são os contatos válidos do tipo do canal; o não perturbe e o inválido não são oferecidos" do
    add_contact(@maria, "phone", "(11) 98765-4321")
    add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20))
    add_contact(@maria, "phone", "(11) 2222-1111", status: "invalid", reason: "errado")
    add_contact(@maria, "email", "maria@exemplo.com.br")
    add_address(@maria, { street: "Rua das Flores", number: "120", city: "São Paulo", state: "SP", zip: "01001-000" })
    entrar(users(:joana))

    get new_customer_contact_attempt_path(@maria), params: { contact_attempt: { channel: "whatsapp" } }, headers: htmx
    assert_select "datalist#contatos-do-cliente option", 1
    assert_select "datalist#contatos-do-cliente option[value='(11) 98765-4321']"
    get new_customer_contact_attempt_path(@maria), params: { contact_attempt: { channel: "email" } }, headers: htmx
    assert_select "datalist#contatos-do-cliente option[value='maria@exemplo.com.br']", 1
    get new_customer_contact_attempt_path(@maria), params: { contact_attempt: { channel: "letter" } }, headers: htmx
    assert_select "datalist#contatos-do-cliente option[value='Rua das Flores, 120, São Paulo/SP, CEP 01001-000']", 1
    get form_customer_contact_attempts_path(@maria), headers: painel
    assert_select "datalist#contatos-do-cliente option", 3
  end

  test "R120 (critério de aceite): digitar um contato em não perturbe avisa com a data e o registro é aceito; inválido também avisa" do
    add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20))
    add_contact(@maria, "phone", "(11) 2222-1111", status: "invalid", reason: "errado")
    entrar(users(:joana))
    result = result_of(@alfa, :no_answer)

    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "(11) 3333-4444" } }, headers: painel
    assert_response :no_content
    assert_match(/este contato está em não perturbe desde 20\/10\/2026/i, notice_of_panel)
    assert_equal "warning", JSON.parse(response.headers["HX-Trigger"]).dig("painel:concluido", "tom")
    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "11 2222-1111" } }, headers: painel
    assert_match(/está inválido \(errado\)/, notice_of_panel)
    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "(11) 97777-7777" } }, headers: painel
    assert_no_match(/não perturbe|inválido/, notice_of_panel)
    assert_equal 3, @maria.contact_attempts.count
  end

  test "R121 (critério de aceite): 'Número ou endereço inexistente' marca o contato usado como inválido, com o motivo, e o histórico registra" do
    contact = add_contact(@maria, "phone", "(11) 98765-4321")
    other = add_contact(@maria, "phone", "(11) 97777-7777")
    entrar(users(:carlos))

    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result_of(@alfa, :wrong_number).id, contact_used: "11 98765-4321" } }

    contact.reload
    assert_equal "invalid", contact.status
    assert_match(/\Ainexistente, acionamento de \d\d\/\d\d\z/, contact.reason)
    assert_equal "valid", other.reload.status
    change = Change.find_by!(subject_type: "customer_contact", subject_id: contact.id)
    assert_equal [ "invalidated_by_result", "contact_attempt", users(:carlos).id ], [ change.event, change.origin, change.user_id ]
  end

  test "R121 e R123: o resultado do gestor marcado 'invalida o contato' também invalida; a marca só é editada por quem gerencia resultados" do
    result = result_of(@alfa, :says_paid)
    contact = add_contact(@maria, "phone", "(11) 98765-4321")
    entrar(users(:joana))

    get edit_settings_contact_result_path(result)
    assert_select "input[type=checkbox][name='contact_result[invalidates_contact]']"
    patch settings_contact_result_path(result), params: { contact_result: { name: result.name, return_rule: result.return_rule, invalidates_contact: "1" } }
    assert result.reload.invalidates_contact?
    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "whatsapp", result_id: result.id, contact_used: "11987654321" } }
    assert_equal "invalid", contact.reload.status
    assert_equal [ "Número ou endereço inexistente" ], ContactResult.where(tenant: @alfa, invalidates_contact: true).where.not(id: result.id).pluck(:name), "na lista inicial só 'inexistente' vem marcado"
    get settings_contact_results_path
    assert_select "th", text: "Invalida o contato"
  end

  test "R122 (critério de aceite): digitar um contato novo e marcar 'salvar' cria o contato, origem acionamento; sem a marca fica só no acionamento" do
    entrar(users(:joana))
    result = result_of(@alfa, :no_answer)

    get form_customer_contact_attempts_path(@maria), headers: painel
    assert_select "input[type=checkbox][name='contact_attempt[save_contact]']"
    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "(11) 4444-5555" } }
    assert_equal 0, @maria.contacts.count
    travel 11.seconds # passa a janela que ignora o duplo envio
    post customer_contact_attempts_path(@maria), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "(11) 4444-5555", save_contact: "1" } }

    contact = @maria.contacts.sole
    assert_equal [ "valid", "contact_attempt", "(11) 4444-5555" ], [ contact.status, contact.origin, contact.value ]
    assert_equal "contact_attempt", Change.find_by!(subject_type: "customer_contact", subject_id: contact.id).origin
  end

  test "R122 e PD5 (critério de aceite): Marta tem o campo 'salvar' para a Alfa e não para a Beta, e o envio direto na Beta é ignorado" do
    entrar(marta)
    result = result_of(@beta, :no_answer)

    get form_customer_contact_attempts_path(@maria), headers: painel
    assert_select "input[type=checkbox][name='contact_attempt[save_contact]']", 1
    get form_customer_contact_attempts_path(@beta_customer), headers: painel
    assert_select "input[name='contact_attempt[save_contact]']", 0

    post customer_contact_attempts_path(@beta_customer), params: { contact_attempt: { channel: "phone", result_id: result.id, contact_used: "(11) 4444-5555", save_contact: "1" } }
    assert_equal [ 1, 0 ], [ @beta_customer.contact_attempts.count, @beta_customer.contacts.count ]
  end

  test "R122: sem a permissão 12 (só registrar acionamentos), o campo 'salvar' não aparece" do
    entrar(users(:carlos))
    users(:carlos).memberships.first.profile.update!(permissions: %w[view_portfolio record_contact_attempts])

    get form_customer_contact_attempts_path(@maria), headers: painel
    assert_select "form.painel[hx-post]", 1
    assert_select "input[name='contact_attempt[save_contact]']", 0
  end

  # ---- Dados do credor (R106) e política (R117) ----

  test "R106 (critério de aceite): o gestor recusa CNPJ inválido, salva com razão social, e o painel mostra o nome fantasia" do
    entrar(users(:joana))

    get settings_tenant_registry_path
    assert_response :success
    assert_select "h1", "Dados do credor"
    patch settings_tenant_registry_path, params: { tenant_id: @alfa.id, tenant: { cnpj: "11.111.111/1111-11", legal_name: "Comércio Exemplo Ltda", trade_name: "Exemplo" } }
    assert_response :unprocessable_content
    assert_select "aside", text: /CNPJ inválido/
    assert_nil @alfa.reload.cnpj

    patch settings_tenant_registry_path, params: { tenant_id: @alfa.id, tenant: { cnpj: "11.222.333/0001-81", legal_name: "Comércio Exemplo Ltda", trade_name: "Exemplo", phone: "(11) 3000-1000" } }
    assert_redirected_to settings_tenant_registry_path
    follow_redirect!
    assert_select "aside", text: /Dados de Escola Alfa salvos/
    assert_select "input[name='tenant[cnpj]'][value='11.222.333/0001-81']"
    assert_select "p", text: /Última alteração: Joana Souza/
    get root_path
    assert_select "section header p", text: /Exemplo/, count: 0 # o resumo só tem totais, sem nome de credor (25/10/2026)
  end

  test "R106 e R106a (critério de aceite): Marta com a 4 nas duas vê e edita o cadastro de cada credor separadamente; a edição de outro credor é recusada" do
    user = marta
    entrar(user)

    get settings_tenant_registry_path
    assert_select "section h2", text: "Escola Alfa"
    assert_select "section h2", text: "Clínica Beta"
    patch settings_tenant_registry_path, params: { tenant_id: @beta.id, tenant: { legal_name: "Clínica Beta SA", trade_name: "Beta" } }
    assert_equal [ "Beta", nil ], [ @beta.reload.display_name, @alfa.reload.trade_name ]

    only_alfa = make_user(@alfa, %w[change_settings])
    delete session_path
    entrar(only_alfa)
    patch settings_tenant_registry_path, params: { tenant_id: @beta.id, tenant: { legal_name: "Invasão" } }
    assert_response :not_found
    assert_equal "Clínica Beta SA", @beta.reload.legal_name
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id
  end

  test "quem não tem 'alterar configuração' não vê a aba Dados do credor nem abre a tela" do
    entrar(users(:carlos))

    get settings_tenant_registry_path
    assert_response :not_found
    get root_path
    assert_select "nav.secoes a", text: "Dados do credor", count: 0
  end

  test "R117: a política 'Correção na tela ou carga' é um cartão na aba Carteira, com padrão 'a tela prevalece', salva por credor com o histórico" do
    entrar(users(:joana))

    get settings_portfolio_path
    assert_select ".politica .titulo", text: /Correção na tela ou carga: qual vale/
    assert_select "input[name=correction_policy][value=screen][checked]"
    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "correction", correction_policy: "load" }
    assert_redirected_to settings_portfolio_path
    follow_redirect!

    assert_equal [ "load", "screen" ], [ @alfa.setting.reload.correction_policy, @beta.setting.correction_policy ]
    assert_select "p", text: /Alterada por Joana Souza/
    assert_equal [ "screen", "load" ], Change.where(subject_type: "settings", field: "correction_policy").pluck(:before, :after).first
    patch settings_portfolio_path, params: { tenant_id: @alfa.id, section: "correction", correction_policy: "qualquer" }
    assert_response :unprocessable_content
  end

  test "o Operador padrão recebe 'editar cadastro de cliente' e o credor novo também" do
    assert_includes Permission::OPERATOR, "edit_customer_registry"
    assert_includes Tenant.provision!("Credor novo").profiles.find_by!(name: "Operador").permissions, "edit_customer_registry"
  end

  test "a conferência da carga mostra os avisos de contato e o que é mantido pelo credor" do
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva Souza")
    entrar(users(:joana))
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "c.csv",
      file: write_csv([ { "documento" => "529.982.247-25", "nome" => "Maria da Silva", "titulo" => "NF-1", "vencimento" => "10/09/2026", "valor" => "10,00", "telefone" => "123", "contrato" => "CT-1" } ],
                      header: %w[documento nome titulo vencimento valor telefone contrato]))
    perform_enqueued_jobs(only: CheckImportJob)

    get import_path(import)

    assert_select "#contatos-da-conferencia", text: /linha 2: telefone ignorado \(menos de 8 dígitos\)/
    assert_select "#mantidos-pelo-credor", text: /1 nome/
    assert_select "#mantidos-pelo-credor", text: /Maria da Silva Souza.*Maria da Silva.*mantido pelo credor/m
  end
end
