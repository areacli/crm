require "test_helper"

# Telas de acionamentos (04): ficha, registro, lista, resumo e resultados. Permissões 1, 7 e 9 por credor e isolamento (V10).
class ContactAttemptsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @maria = make_customer(@alfa)
    @beta_customer = make_customer(@beta, name: "Cliente da Beta")
  end

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def register(customer, result, overrides = {}, headers: {})
    post customer_contact_attempts_path(customer), params: { contact_attempt: { channel: "phone", result_id: result.id }.merge(overrides) }, headers: headers
  end

  # Marta da especificação: registra e consulta na Alfa, só consulta na Beta.
  def marta_in_two_tenants(extra_alfa: %w[record_contact_attempts])
    user = make_user(@alfa, extra_alfa)
    Membership.create!(user: user, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    user
  end

  # ---- Ficha: formulário e histórico ----

  test "R76: o operador vê o formulário e o histórico na ficha; quem só consulta vê o histórico sem o formulário" do
    insert_attempt(@maria, user: users(:carlos), text: "Recebe dia 20")
    entrar(users(:carlos))
    get customer_path(@maria)
    assert_response :success
    assert_select "form#registrar-acionamento-form, form[aria-labelledby=registrar-acionamento]", 1
    assert_select "select[name='contact_attempt[result_id]'] option", text: "Não atendeu"
    assert_select "td p.texto-do-operador", text: "Recebe dia 20"

    delete session_path
    viewer = make_user(@alfa, [])
    entrar(viewer)
    get customer_path(@maria)
    assert_response :success
    assert_select "form[aria-labelledby=registrar-acionamento]", 0
    assert_select "#historico-acionamentos table"
  end

  test "o endereço de registro de quem não tem a permissão 7 responde 404 e a recusa fica registrada (R33)" do
    entrar(make_user(@alfa, []))
    assert_no_difference "ContactAttempt.count" do
      register(@maria, result_of(@alfa, :no_answer))
    end
    assert_response :not_found
    assert_equal @alfa.id, AccessEvent.where(event: "access_denied").last.tenant_id
  end

  test "R76 e V10: a permissão vale no credor do cliente; com 7 só na Alfa, a ficha da Beta não tem o formulário e o envio é recusado e registrado" do
    entrar(marta_in_two_tenants)
    get customer_path(@beta_customer)
    assert_response :success
    assert_select "form[aria-labelledby=registrar-acionamento]", 0

    assert_no_difference "ContactAttempt.count" do
      register(@beta_customer, result_of(@beta, :no_answer))
    end
    assert_response :not_found
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id
    assert_response :not_found

    assert_difference "ContactAttempt.count", 1 do
      register(@maria, result_of(@alfa, :no_answer))
    end
  end

  test "V10: sem acesso ao credor do cliente, ficha, histórico, campos e registro respondem 404" do
    entrar(users(:marta))
    get customer_path(@maria)
    assert_response :not_found
    get customer_contact_attempts_path(@maria), headers: htmx
    assert_response :not_found
    get new_customer_contact_attempt_path(@maria), headers: htmx
    assert_response :not_found
    assert_no_difference "ContactAttempt.count" do
      register(@maria, result_of(@alfa, :no_answer))
    end
    assert_response :not_found
  end

  test "critério de aceite: o acionamento registrado pelo htmx aparece no topo do histórico, com o formulário limpo" do
    entrar(users(:joana))
    register(@maria, result_of(@alfa, :no_answer), { contact_used: "(11) 98765-4321" }, headers: htmx)
    assert_response :success
    assert_select "#form-acionamento [role=status]", text: /Acionamento registrado/
    assert_select "#historico-acionamentos[hx-swap-oob=true] tbody tr:first-child" do
      assert_select "td", text: /Telefone/
      assert_select "td small", text: "(11) 98765-4321"
      assert_select "td", text: /Não atendeu/
      assert_select "td", text: /Joana Souza/
    end
    assert_equal 1, @maria.contact_attempts.count
  end

  test "sem JavaScript o registro volta para a ficha com a mensagem" do
    entrar(users(:joana))
    register(@maria, result_of(@alfa, :no_answer))
    assert_redirected_to customer_path(@maria, anchor: "acionamentos")
    follow_redirect!
    assert_select "[role=status]", text: /Acionamento registrado/

    register(@maria, result_of(@alfa, :call_back))
    assert_redirected_to customer_path(@maria, anchor: "acionamentos")
    follow_redirect!
    assert_select "[role=alert]", text: /exige data de retorno/
  end

  test "R73: resultado que exige retorno sem a data é recusado com a mensagem e o que foi digitado fica no formulário" do
    entrar(users(:joana))
    register(@maria, result_of(@alfa, :call_back), { text: "Recebe o salário dia 20", contact_used: "(11) 3333-4444" }, headers: htmx)
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /este resultado exige data de retorno/i
    assert_select "textarea", text: /Recebe o salário dia 20/
    assert_select "input[name='contact_attempt[contact_used]'][value='(11) 3333-4444']"
    assert_select "select[name='contact_attempt[result_id]'] option[selected]", text: "Pediu para retornar depois"
    assert_select "input[name='contact_attempt[return_at]'][required]"
    assert_equal 0, ContactAttempt.count

    future = 2.days.from_now.strftime("%Y-%m-%dT%H:%M")
    register(@maria, result_of(@alfa, :call_back), { return_at: future }, headers: htmx)
    assert_response :success
    assert_select "tbody td", text: /Pediu para retornar depois/
  end

  test "R73: os campos que dependem do resultado: o retorno some se o resultado não permite, é obrigatório se exige e opcional se permite" do
    entrar(users(:joana))
    fields = ->(result) { get new_customer_contact_attempt_path(@maria), params: { contact_attempt: { result_id: result.id } }, headers: htmx }

    fields.call(result_of(@alfa, :wrong_number))
    assert_response :success
    assert_select "#campo-retorno[hx-swap-oob=true]"
    assert_select "#campo-retorno input", 0

    fields.call(result_of(@alfa, :call_back))
    assert_select "#campo-retorno input[type='datetime-local'][required]"

    fields.call(result_of(@alfa, :negotiating))
    assert_select "#campo-retorno input[type='datetime-local']"
    assert_select "#campo-retorno input[required]", 0

    get new_customer_contact_attempt_path(@maria)
    assert_redirected_to customer_path(@maria, anchor: "acionamentos")
  end

  test "R72: o texto aparece exatamente como digitado, em duas linhas, e nenhum código é executado" do
    entrar(users(:joana))
    register(@maria, result_of(@alfa, :no_answer), { text: "<script>alert(1)</script>\nsegunda linha" })
    get customer_path(@maria)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;\nsegunda linha"
    assert_not_includes response.body, "<script>alert(1)</script>"
  end

  test "R74: a ficha mostra os 20 mais recentes pela data do contato e leva aos 5 restantes" do
    25.times { |index| insert_attempt(@maria, contacted_at: (index + 1).hours.ago, text: "contato #{index + 1}") }
    entrar(users(:joana))
    get customer_path(@maria)
    assert_select "#historico-acionamentos tbody tr", 20
    assert_select "#historico-acionamentos tbody tr:first-child", text: /contato 1\b/
    assert_select "#historico-acionamentos", text: /Mostrando 1 a 20 de 25/
    assert_select "#historico-acionamentos a[rel=next][data-hx-get]"

    get customer_contact_attempts_path(@maria, page: 2), headers: htmx
    assert_select "tbody tr", 5
    assert_select "tbody tr:first-child", text: /contato 21\b/
    assert_select "#historico-acionamentos[hx-trigger*='cable:contact-attempts-changed']"
  end

  test "R69b e R69c: o contrato aparece no histórico e o aviso do responsável financeiro é só sugestão, sem bloquear" do
    ana = @maria
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    contract = Contract.find_by!(tenant: @alfa, code: "CT-1")
    ContractCustomer.where(contract: contract, customer: ana).update_all(roles: %w[holder financial_responsible])
    ContractCustomer.where(contract: contract, customer: pedro).update_all(roles: %w[holder])
    entrar(users(:joana))

    get new_customer_contact_attempt_path(pedro), params: { contact_attempt: { contract_id: contract.id } }, headers: htmx
    assert_select "#aviso-contrato[hx-swap-oob=true] .aviso", text: /O responsável financeiro deste contrato é Maria Souza/
    get new_customer_contact_attempt_path(ana), params: { contact_attempt: { contract_id: contract.id } }, headers: htmx
    assert_select "#aviso-contrato .aviso", 0

    register(pedro, result_of(@alfa, :no_answer), { contract_id: contract.id })
    assert_redirected_to customer_path(pedro, anchor: "acionamentos")
    get customer_path(pedro)
    assert_select "#historico-acionamentos th small", text: "Contrato CT-1"
    get customer_path(ana)
    assert_select "#historico-acionamentos tbody tr", 0
  end

  test "R69c e MT-16: sem responsável financeiro declarado, os titulares são os sugeridos" do
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    contract = Contract.find_by!(tenant: @alfa, code: "CT-1")
    ContractCustomer.where(contract: contract).update_all(roles: %w[holder])
    form = Contacts::Form.new(pedro, { contract_id: contract.id })
    assert_nil form.other_responsible_names

    third = make_customer(@alfa, document: "111.444.777-35", name: "Terceira Pessoa", contract_code: "CT-2")
    ContractCustomer.create!(contract: contract, customer: third, roles: [])
    assert_equal [ "Maria Souza", "Pedro Souza" ], Contacts::Form.new(third, { contract_id: contract.id }).other_responsible_names
  end

  test "R71: os contatos oferecidos são os do cliente contatado, nunca os de outro cliente do contrato" do
    add_contact(@maria, "phone", "(11) 98765-4321")
    add_contact(@maria, "email", "maria@exemplo.com.br")
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    entrar(users(:joana))

    get customer_path(pedro)
    assert_select "datalist#contatos-do-cliente option", 0
    get customer_path(@maria)
    assert_select "datalist#contatos-do-cliente option[value='(11) 98765-4321']"
    assert_select "datalist#contatos-do-cliente option[value='maria@exemplo.com.br']"
  end

  test "R67: o resultado desativado só na Alfa não é oferecido lá e continua na Beta (e o antigo mantém o nome)" do
    attempt = insert_attempt(@maria, result: result_of(@alfa, :voicemail))
    result_of(@alfa, :voicemail).update!(active: false)
    entrar(users(:ana))

    get customer_path(@maria)
    assert_select "select[name='contact_attempt[result_id]'] option", text: "Caixa postal", count: 0
    assert_select "#historico-acionamentos td", text: /Caixa postal/
    get customer_path(@beta_customer)
    assert_select "select[name='contact_attempt[result_id]'] option", text: "Caixa postal"
    assert attempt.reload.result.name == "Caixa postal"
  end

  test "resultado desativado entre abrir a ficha e registrar: recusado com a mensagem" do
    entrar(users(:joana))
    result = result_of(@alfa, :voicemail)
    result.update!(active: false)
    register(@maria, result, { text: "meu texto" }, headers: htmx)
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Resultado desativado; escolha outro/
    assert_select "textarea", text: /meu texto/
  end

  # ---- Imutabilidade (revisão 5) ----

  test "revisão 5: não há anulação nem edição: sem botão na ficha e sem rota de anulação" do
    attempt = insert_attempt(@maria, user: users(:carlos))
    entrar(users(:joana))
    get customer_path(@maria)
    assert_select "button", text: /Anular/, count: 0
    assert_select "dialog:not(#exportar-dados):not(#anonimizar-cliente):not(#transferir-credito)", 0
    post "/acionamentos/#{attempt.id}/anulacao", params: { void: { reason: "x" } }
    assert_response :not_found
    patch "/clientes/#{@maria.id}/acionamentos/#{attempt.id}", params: { contact_attempt: { text: "x" } }
    assert_response :not_found
    delete "/clientes/#{@maria.id}/acionamentos/#{attempt.id}"
    assert_response :not_found
    assert ContactAttempt.exists?(attempt.id)
  end

  # ---- Lista de acionamentos (R78) ----

  def build_week
    joana, pedro = users(:joana), users(:carlos)
    3.times { |index| insert_attempt(@maria, user: joana, contacted_at: (index + 1).hours.ago, text: "da Joana #{index}") }
    2.times { |index| insert_attempt(@maria, user: pedro, contacted_at: (index + 5).hours.ago, text: "do Pedro #{index}") }
    @old = insert_attempt(@maria, user: joana, contacted_at: 10.days.ago, text: "de dez dias atrás")
  end

  test "critério de aceite: a lista abre com os últimos 7 dias; os filtros reduzem e o período maior amplia" do
    build_week
    entrar(users(:joana))
    get contact_attempts_path
    assert_response :success
    assert_select "#resultado tbody tr", 5
    assert_select "#resultado", text: /Mostrando 1 a 5 de 5 acionamentos/
    assert_select "th", text: "Credor", count: 0

    get contact_attempts_path(operator: users(:joana).id)
    assert_select "#resultado tbody tr", 3
    get contact_attempts_path(from: 12.days.ago.to_date.iso8601)
    assert_select "#resultado tbody tr", 6
    assert_select "#resultado td", text: /Maria Souza/, minimum: 1
    assert_select "label", text: /anulados/, count: 0
  end

  test "R78: filtros de canal, resultado e tipo, e o período vai no máximo a 92 dias" do
    insert_attempt(@maria, channel: "whatsapp", result: result_of(@alfa, :negotiating))
    insert_attempt(@maria, channel: "phone", result: result_of(@alfa, :no_answer))
    insert_attempt(@maria, channel: "phone", result: result_of(@alfa, :voicemail), contacted_at: 60.days.ago)
    insert_attempt(@maria, channel: "phone", result: result_of(@alfa, :voicemail), contacted_at: 100.days.ago)
    entrar(users(:joana))

    get contact_attempts_path(channel: "whatsapp")
    assert_select "#resultado tbody tr", 1
    get contact_attempts_path(result: result_of(@alfa, :no_answer).id)
    assert_select "#resultado tbody tr", 1
    get contact_attempts_path(kind: "spoke_with_customer")
    assert_select "#resultado tbody tr", 1
    assert_select "#resultado tbody td", text: "Falou com o cliente"

    get contact_attempts_path(from: 200.days.ago.to_date.iso8601, to: Date.current.iso8601)
    assert_select "#resultado tbody tr", 3
    assert_select "input[name=from][value='#{(Date.current - 92).iso8601}']"
    get contact_attempts_path(from: "lixo", to: "")
    assert_response :success
  end

  test "R78: a busca refaz só o trecho e a lista se atualiza pelos avisos do WebSocket" do
    build_week
    entrar(users(:joana))
    get contact_attempts_path(operator: users(:carlos).id), headers: htmx
    assert_not_includes response.body, "<html"
    assert_select "#resultado[hx-trigger*='cable:contact-attempts-changed'][hx-get*='operator']"
    assert_select "#resultado tbody tr", 2

    get contact_attempts_path
    assert_select "meta[name=cable-channels][content*='ContactAttemptsChannel']"
  end

  test "P22: a lista abre com 20 por página e oferece 50 e 100" do
    22.times { |index| insert_attempt(@maria, contacted_at: (index + 1).minutes.ago) }
    entrar(users(:joana))
    get contact_attempts_path
    assert_select "#resultado tbody tr", 20
    assert_select "#resultado a[rel=next]"
    get contact_attempts_path(per_page: 50)
    assert_select "#resultado tbody tr", 22
  end

  test "R78 e V10: com consulta nos dois credores a lista mistura os dois, com a coluna Credor e o filtro; com a Beta só, nada da Alfa aparece" do
    insert_attempt(@maria)
    insert_attempt(@beta_customer, user: users(:ana))
    entrar(users(:ana))

    get contact_attempts_path
    assert_select "#resultado tbody tr", 2
    assert_select "th", text: "Credor"
    assert_select "select#tenant option", 3
    get contact_attempts_path(tenant: @beta.id)
    assert_select "#resultado tbody tr", 1
    assert_select "#resultado td", text: "Clínica Beta"

    delete session_path
    entrar(users(:marta))
    get contact_attempts_path
    assert_select "#resultado tbody tr", 1
    assert_select "#resultado", text: /Maria Souza/, count: 0
    get contact_attempts_path(tenant: @alfa.id)
    assert_select "#resultado tbody tr", 0
    assert_select "select#operator option", text: "Joana Souza", count: 0
    assert_select "select#result option", text: /Não atendeu/, count: 1
  end

  test "R78: sem a permissão de consultar a carteira em nenhum credor a lista responde 404" do
    user = User.create!(name: "Sem perfil", email_address: "semperfil@exemplo.com.br", password: "senha-de-teste-1")
    Membership.create!(user: user, tenant: @alfa, profile: Profile.create!(tenant: @alfa, name: "Vazio", permissions: []))
    entrar(user)
    get contact_attempts_path
    assert_response :not_found
  end

  # ---- Resumo (R79) ----

  test "critério de aceite R79: o resumo conta acionamentos e clientes acionados nos últimos 7 dias, no total e por tipo" do
    mario = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Mário")
    2.times { insert_attempt(@maria, result: result_of(@alfa, :no_answer)) }
    insert_attempt(@maria, result: result_of(@alfa, :negotiating))
    insert_attempt(mario, result: result_of(@alfa, :third_party_message))
    insert_attempt(mario, result: result_of(@alfa, :no_answer), contacted_at: 20.days.ago)
    entrar(users(:joana))

    get root_path
    rows = css_select("section[aria-labelledby='acionamentos'] tbody tr").map { |row| row.css("th, td").map { |cell| cell.text.strip } }
    assert_equal [ [ "Total", "4", "2", "5", "2" ], [ "Falou com o cliente", "1", "1", "1", "1" ], [ "Falou com terceiro", "1", "1", "1", "1" ],
                   [ "Sem contato", "2", "1", "3", "2" ] ], rows
  end

  test "R79 e MT-9: um bloco só, somado, e o mesmo CPF acionado nos dois credores conta um cliente em cada (clientes são por credor)" do
    insert_attempt(@maria)
    insert_attempt(@beta_customer, user: users(:ana))
    entrar(users(:ana))

    get root_path
    assert_select "section[aria-labelledby='acionamentos'] tbody tr:first-child", text: /Total\s*2\s*2/
    assert_select "section", text: /Acionamentos — /, count: 0

    delete session_path
    entrar(users(:marta))
    get root_path
    assert_select "section[aria-labelledby='acionamentos'] tbody tr:first-child", text: /Total\s*1\s*1/
  end

  # ---- Resultados de acionamento (configuração) ----

  test "R66: o operador não abre a configuração dos resultados; o gestor vê só os credores em que tem a permissão 9" do
    entrar(users(:carlos))
    get settings_contact_results_path
    assert_response :not_found

    delete session_path
    entrar(users(:ana))
    get settings_contact_results_path
    assert_response :success
    assert_select "h2", text: "Clínica Beta"
    assert_select "h2", text: "Escola Alfa", count: 0
    assert_select "nav.abas a[aria-current=page]", text: "Resultados de acionamento"
  end

  test "critério de aceite: o gestor cria 'Pediu boleto por e-mail', ele aparece na escolha do registro e a criação fica no histórico" do
    entrar(users(:joana))
    post settings_contact_results_path, params: { contact_result: { tenant_id: @alfa.id, name: "Pediu boleto por e-mail", kind: "spoke_with_customer", return_rule: "allowed" } }
    assert_redirected_to settings_contact_results_path
    result = ContactResult.find_by!(name: "Pediu boleto por e-mail")
    assert_equal @alfa.id, result.tenant_id
    assert_not ContactResult.exists?(tenant: @beta, name: "Pediu boleto por e-mail")
    get customer_path(@maria)
    assert_select "select[name='contact_attempt[result_id]'] option", text: "Pediu boleto por e-mail"
    assert_equal "created", Change.where(subject_type: "contact_result", subject_id: result.id).sole.event
  end

  test "R66: nome repetido no credor é recusado; o tipo não é editável, mas o nome e a regra de retorno são" do
    entrar(users(:joana))
    post settings_contact_results_path, params: { contact_result: { tenant_id: @alfa.id, name: "caixa POSTAL", kind: "no_contact", return_rule: "allowed" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /já existe um resultado com esse nome neste credor/

    result = result_of(@alfa, :wrong_number)
    get edit_settings_contact_result_path(result)
    assert_select "select[name='contact_result[kind]'][disabled]"
    patch settings_contact_result_path(result), params: { contact_result: { name: "Número errado", return_rule: "allowed", kind: "spoke_with_customer" } }
    assert_redirected_to settings_contact_results_path
    result.reload
    assert_equal [ "Número errado", "allowed", "no_contact" ], result.values_at(:name, :return_rule, :kind)
  end

  test "R67: o resultado só se desativa e reativa (não há exclusão) e sobe e desce na lista" do
    entrar(users(:joana))
    result = result_of(@alfa, :voicemail)
    get settings_contact_results_path
    assert_select "tr#resultado-#{result.id} .situacao", text: "Ativo"
    assert_select "tr#resultado-#{result.id} form[action$='/ativacao'] button", text: "Desativar"
    assert_select "button", text: /Apagar|Excluir/, count: 0

    delete settings_contact_result_activation_path(result)
    assert_not result.reload.active?
    get settings_contact_results_path
    assert_select "tr#resultado-#{result.id} .situacao", text: "Desativado"
    post settings_contact_result_activation_path(result)
    assert result.reload.active?

    position = result.position
    post settings_contact_result_movement_path(result), params: { movement: { direction: "up" } }
    assert_equal position - 1, result.reload.position
    post settings_contact_result_movement_path(result), params: { movement: { direction: "sideways" } }
    assert_response :unprocessable_content
  end

  test "V10: o gestor da Alfa não cria, edita, desativa nem move resultado da Beta (404 registrado)" do
    entrar(users(:joana))
    beta_result = result_of(@beta, :voicemail)
    assert_no_difference "ContactResult.count" do
      post settings_contact_results_path, params: { contact_result: { tenant_id: @beta.id, name: "Intruso", kind: "no_contact", return_rule: "allowed" } }
    end
    assert_response :not_found

    get edit_settings_contact_result_path(beta_result)
    assert_response :not_found
    patch settings_contact_result_path(beta_result), params: { contact_result: { name: "Mudado", return_rule: "allowed" } }
    assert_response :not_found
    delete settings_contact_result_activation_path(beta_result)
    assert_response :not_found
    post settings_contact_result_movement_path(beta_result), params: { movement: { direction: "up" } }
    assert_response :not_found
    beta_result.reload
    assert_equal [ "Caixa postal", true ], [ beta_result.name, beta_result.active ]
    assert_equal @beta.id, AccessEvent.where(event: "access_denied").last.tenant_id
  end

  test "o menu mostra Acionamentos a quem consulta a carteira e a aba de resultados a quem tem a permissão 9" do
    entrar(users(:carlos))
    get root_path
    assert_select "nav[aria-label=Menu] a", text: "Acionamentos"
    assert_select "nav[aria-label=Menu] a[href='/configuracao']", count: 0
    get "/configuracao/resultados-de-acionamento"
    assert_response :not_found

    delete session_path
    entrar(users(:joana))
    get settings_portfolio_path
    assert_select "nav.abas a", text: "Resultados de acionamento"
  end
end
