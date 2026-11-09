require "test_helper"

# Tela de usuários (especificação 02): R33, R36, R36a, R37, R40, R41, R42 e o isolamento por credor (V10).
class MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  test "sem a permissão 10 o endereço é recusado e registrado, sem dado de outros usuários (R33)" do
    sign_in_as users(:carlos)

    get memberships_url, headers: TRECHO
    assert_response :not_found
    assert_not_includes response.body, "joana@exemplo.com.br"
    get membership_url(memberships(:joana_alfa)), headers: TRECHO
    assert_response :not_found
    post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "x@exemplo.com.br", name: "X", profile_id: profiles(:alfa_operator).id } }
    assert_response :not_found

    assert_equal 3, AccessEvent.where(event: "access_denied", user: users(:carlos)).count
    assert_nil User.find_by(email_address: "x@exemplo.com.br")
  end

  test "o menu do operador não mostra Usuários nem Perfis; o do gestor mostra" do
    sign_in_as users(:carlos)
    assert_empty rotulos_do_menu & [ "Usuários", "Perfis" ]

    sign_in_as users(:joana)
    assert_empty [ "Usuários", "Perfis" ] - rotulos_do_menu
  end

  test "a lista traz só os vínculos dos credores com a permissão 10, sem coluna Credor com um só credor (V10)" do
    sign_in_as users(:joana)

    get memberships_url, headers: TRECHO

    assert_response :success
    assert_select "tbody th a", text: "Joana Souza"
    assert_select "tbody th a", text: "Carlos Lima"
    assert_select "th", text: "Credor", count: 0
    assert_not_includes response.body, "Marta Nunes"
  end

  test "com a permissão 10 em dois credores a lista traz a coluna Credor e o filtro" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    sign_in_as users(:ana)

    get memberships_url, headers: TRECHO
    assert_select "th", text: "Credor"
    assert_select "tbody tr", 6
    assert_select "select#tenant"

    get memberships_url(credor: @beta.id), headers: TRECHO
    assert_select "tbody tr", 2
    assert_not_includes response.body, "Carlos Lima"
  end

  test "a busca por nome ou e-mail refaz só o resultado" do
    sign_in_as users(:joana)

    get memberships_url(busca: "carl"), headers: TRECHO.merge("X-CRM-Fragmento" => "1")

    assert_response :success
    assert_select "header", false
    assert_select "#resultado tbody tr", 1
  end

  test "a ficha de um vínculo de outro credor é recusada por link direto e registrada com o credor (V10, R42)" do
    sign_in_as users(:joana)

    get membership_url(memberships(:ana_beta)), headers: TRECHO
    assert_response :not_found
    patch membership_profile_url(memberships(:ana_beta)), params: { membership: { profile_id: profiles(:beta_operator).id } }
    assert_response :not_found
    delete membership_activation_url(memberships(:marta_beta))
    assert_response :not_found
    post membership_password_reset_url(memberships(:marta_beta))
    assert_response :not_found

    assert_equal profiles(:beta_manager), memberships(:ana_beta).reload.profile
    assert memberships(:marta_beta).reload.active?
    assert_equal [ @beta.id ], AccessEvent.where(event: "access_denied", user: users(:joana)).pluck(:tenant_id).uniq
  end

  test "R36 e R37: cria o operador, mostra a senha temporária uma única vez e o histórico não a guarda" do
    sign_in_as users(:joana)

    post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "Joana.Souza@Credor.example", name: "Joana de Souza", profile_id: profiles(:alfa_operator).id } }

    assert_redirected_to memberships_url
    seguir_redirecionamento!
    password = response.body[%r{<code>([^<]+)</code>}, 1]
    assert_match(/\A[a-zA-Z2-9]{4}(-[a-zA-Z2-9]{4}){3}\z/, password)
    assert_select "[role=status]", /não será mostrada de novo/
    assert_select "[role=status]", /joana.souza@credor.example/

    get memberships_url, headers: TRECHO
    assert_not_includes response.body, password

    user = User.find_by!(email_address: "joana.souza@credor.example")
    assert_equal profiles(:alfa_operator), user.memberships.sole.profile
    get membership_url(user.memberships.sole), headers: TRECHO
    assert_not_includes response.body, password
    assert_select "td", /Usuário criado com o perfil Operador/
  end

  test "R36: nome ausente, e-mail inválido ou perfil de outro credor voltam ao formulário com o motivo" do
    sign_in_as users(:joana)

    post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "novo@exemplo.com.br", name: "", profile_id: profiles(:alfa_operator).id } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Informe o nome/

    post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "isto-nao-e-email", name: "Fulano", profile_id: profiles(:alfa_operator).id } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /E-mail/

    post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "fulano@exemplo.com.br", name: "Fulano", profile_id: profiles(:beta_operator).id } }
    assert_response :unprocessable_content
    assert_nil User.find_by(email_address: "fulano@exemplo.com.br")
  end

  test "não cria usuário em credor onde a pessoa não gerencia usuários (V10)" do
    sign_in_as users(:joana)

    post memberships_url, params: { membership: { tenant_id: @beta.id, email_address: "novo@exemplo.com.br", name: "Novo", profile_id: profiles(:beta_operator).id } }

    assert_response :not_found
    assert_nil User.find_by(email_address: "novo@exemplo.com.br")
  end

  test "R36a: o e-mail de quem já existe liga a pessoa ao credor, com aviso a ela, sem mostrar a senha nem os outros credores" do
    sign_in_as users(:joana)

    assert_difference -> { Notice.where(user: users(:marta)).count } => 1 do
      post memberships_url, params: { membership: { tenant_id: @alfa.id, email_address: "MARTA@exemplo.com.br", name: "", profile_id: profiles(:alfa_manager).id } }, headers: TRECHO
    end

    assert_match(/Marta Nunes \(marta@exemplo.com.br\) foi ligado\(a\) a Escola Alfa/, evento_da_spa["aviso"])
    get memberships_url, headers: TRECHO
    assert_select "code", count: 0
    membership = Membership.find_by!(user: users(:marta), tenant: @alfa)

    get membership_url(membership), headers: TRECHO
    assert_response :success
    assert_select "form[action='#{membership_path(membership)}']", count: 0
    assert_select "button", text: "Redefinir a senha", count: 0
    assert_not_includes response.body, "Clínica Beta"
  end

  test "R36a: nome e senha de quem atua em outro credor não têm ação na tela e o servidor recusa" do
    sign_in_as users(:joana)
    membership = memberships(:ana_alfa)

    get membership_url(membership), headers: TRECHO
    assert_select "button", text: "Salvar o nome", count: 0
    assert_select "button", text: "Redefinir a senha", count: 0

    patch membership_url(membership), params: { user: { name: "Outro Nome" } }
    assert_response :not_found
    post membership_password_reset_url(membership)
    assert_response :not_found
    assert_equal "Ana Prado", users(:ana).reload.name
  end

  test "R36 (revisão 3): altera o nome de quem só atua no credor" do
    sign_in_as users(:joana)

    patch membership_url(memberships(:carlos_alfa)), params: { user: { name: "Carlos Alberto" } }

    assert_redirected_to membership_url(memberships(:carlos_alfa))
    assert_equal "Carlos Alberto", users(:carlos).reload.name

    patch membership_url(memberships(:carlos_alfa)), params: { user: { name: "" } }
    assert_redirected_to membership_url(memberships(:carlos_alfa))
    assert_equal "Carlos Alberto", users(:carlos).reload.name
  end

  test "R33: a mudança de perfil vale no clique seguinte de quem está logado" do
    sign_in_as users(:carlos)
    get new_import_url, headers: TRECHO
    assert_response :not_found

    sign_in_as users(:joana)
    patch membership_profile_url(memberships(:carlos_alfa)), params: { membership: { profile_id: profiles(:alfa_manager).id } }
    assert_redirected_to membership_url(memberships(:carlos_alfa))

    sign_in_as users(:carlos)
    get new_import_url, headers: TRECHO
    assert_response :success
    assert_includes rotulos_do_menu, "Configuração"
  end

  test "PD7 e R41: a própria conta não tem as ações, o servidor recusa e a última gestão fica protegida" do
    sign_in_as users(:joana)
    propria = memberships(:joana_alfa)

    get membership_url(propria), headers: TRECHO
    assert_response :success
    assert_select "button", text: "Salvar o perfil", count: 0
    assert_select "button", text: "Desativar o acesso", count: 0

    patch membership_profile_url(propria), params: { membership: { profile_id: profiles(:alfa_operator).id } }
    assert_response :not_found
    delete membership_activation_url(propria)
    assert_response :not_found
    assert_equal profiles(:alfa_manager), propria.reload.profile
    assert propria.active?
  end

  test "R41: outra pessoa com a permissão 10 não desativa a última gestão do credor" do
    memberships(:carlos_alfa).update!(profile: Profile.create!(tenant: @alfa, name: "Só usuários", permissions: %w[view_portfolio manage_users]))
    sign_in_as users(:carlos)

    delete membership_activation_url(memberships(:joana_alfa)), headers: TRECHO.merge("HTTP_REFERER" => membership_url(memberships(:joana_alfa)))

    assert_match(/Ao menos um usuário ativo precisa poder gerenciar usuários e perfis/, evento_da_spa["aviso"])
    assert_equal "danger", evento_da_spa["tom"]
    assert memberships(:joana_alfa).reload.active?
  end

  test "R40: desativar o vínculo derruba o acesso naquele credor na próxima ação, e reativar devolve" do
    sign_in_as users(:joana)
    delete membership_activation_url(memberships(:carlos_alfa))
    assert_redirected_to membership_url(memberships(:carlos_alfa))
    assert_not memberships(:carlos_alfa).reload.active?

    sign_in_as users(:carlos)
    get summary_url, headers: TRECHO
    assert_response :unauthorized

    sign_in_as users(:joana)
    post membership_activation_url(memberships(:carlos_alfa))
    assert memberships(:carlos_alfa).reload.active?
  end

  test "R40: desativar o vínculo na Alfa deixa a Ana operando a Beta, e a ação na Alfa é recusada e registrada" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    sign_in_as users(:ana)
    sign_in_as users(:joana)
    delete membership_activation_url(memberships(:ana_alfa))

    sign_in_as users(:ana)
    get memberships_url, headers: TRECHO
    assert_response :success
    assert_not_includes response.body, "Joana Souza"
    get membership_url(memberships(:joana_alfa)), headers: TRECHO
    assert_response :not_found
    assert AccessEvent.exists?(event: "access_denied", user: users(:ana), tenant: @alfa)
  end

  test "R37: redefinir a senha mostra outra temporária uma única vez, e o histórico registra sem ela" do
    sign_in_as users(:joana)

    post membership_password_reset_url(memberships(:carlos_alfa))

    assert_redirected_to membership_url(memberships(:carlos_alfa))
    seguir_redirecionamento!
    password = response.body[%r{<code>([^<]+)</code>}, 1]
    assert_equal users(:carlos).reload, User.authenticate_by(email_address: "carlos@exemplo.com.br", password: password)
    assert_select "td", /Senha redefinida/

    get membership_url(memberships(:carlos_alfa)), headers: TRECHO
    assert_not_includes response.body, password
  end

  test "R42: o histórico mostra entradas, bloqueios, recusas e alterações, só do credor e das entradas no sistema" do
    sign_in_as users(:joana)
    AccessEvent.record("login", user: users(:carlos))
    AccessEvent.record("login_refused", user: users(:carlos), email_address: "carlos@exemplo.com.br")
    AccessEvent.record("access_denied", user: users(:carlos), tenant: @alfa, details: { path: "/importacoes/nova" })
    AccessEvent.record("access_denied", user: users(:carlos), tenant: @beta, details: { path: "/clientes/9" })
    AccessEvent.record("profile_changed", user: users(:carlos), tenant: @alfa, actor: users(:joana), details: { before: "Operador", after: "Gestor" })

    get membership_url(memberships(:carlos_alfa)), headers: TRECHO

    assert_select "td", "Entrou no sistema"
    assert_select "td", "Tentativa de entrada recusada"
    assert_select "td", "Acesso recusado por falta de permissão (/importacoes/nova)"
    assert_select "td", "Perfil mudou de Operador para Gestor"
    assert_select "td", "Joana Souza"
    assert_not_includes response.body, "/clientes/9"
  end

  test "o formulário de novo usuário troca só o campo de perfil quando o credor muda" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    sign_in_as users(:ana)

    get new_membership_url, headers: TRECHO
    assert_select "select#membership_tenant_id[data-spa-dependentes]"

    get new_membership_url(membership: { tenant_id: @alfa.id }), headers: TRECHO
    assert_select "form", false
    assert_select "#campo-perfil option", 2
    assert_select "#campo-perfil option", text: "Gestor"
  end

  # Na ficha da SPA (fase 7), o nome e o perfil se editam na linha (design system, 7.1): 204 com o valor gravado, 422 com a mensagem junto do campo.
  test "na ficha, o nome e o perfil se editam na linha; a recusa da regra volta junto do campo" do
    sign_in_as users(:joana)
    get membership_url(memberships(:carlos_alfa)), headers: TRECHO
    assert_select "[data-inline]", 2
    assert_select "a, button", text: "Editar o perfil", count: 0

    inline = TRECHO.merge("X-CRM-Inline" => "1")
    patch membership_profile_url(memberships(:carlos_alfa)), params: { membership: { profile_id: profiles(:alfa_manager).id } }, headers: inline
    assert_response :no_content
    assert_equal profiles(:alfa_manager).name, evento_da_spa["valor"]
    assert_equal profiles(:alfa_manager), memberships(:carlos_alfa).reload.profile

    patch membership_url(memberships(:carlos_alfa)), params: { user: { name: "Carlos Lima" } }, headers: inline
    assert_response :no_content
    assert_equal [ "Carlos Lima", true ], evento_da_spa.values_at("valor", "atualizar")

    patch membership_url(memberships(:carlos_alfa)), params: { user: { name: "" } }, headers: inline
    assert_response :unprocessable_content
    assert response.parsed_body["erro"].present?
    assert_equal "Carlos Lima", users(:carlos).reload.name

    # A última gestão do credor fica protegida (R41): a recusa vem para junto da lista de perfis.
    memberships(:carlos_alfa).update!(profile: profiles(:alfa_operator))
    patch membership_profile_url(memberships(:joana_alfa)), params: { membership: { profile_id: profiles(:alfa_operator).id } }, headers: inline
    assert_response :not_found
  end

  test "no diálogo de novo usuário, trocar o credor pede só o campo do perfil, com os perfis dele" do
    sign_in_as users(:joana)
    get new_membership_url(membership: { tenant_id: @alfa.id }), headers: TRECHO
    assert_response :success
    assert_select "[id=campo-perfil][data-fora-de-banda=true] option", text: profiles(:alfa_operator).name
    assert_select "form", count: 0
  end
end
