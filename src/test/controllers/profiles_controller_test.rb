require "test_helper"

# Tela de perfis (especificação 02): R30, R31, R35, R41, PD6, PD7 e o isolamento por credor (V10).
class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  test "sem a permissão 11 a tela é recusada e registrada (R33)" do
    sign_in_as users(:carlos)

    get profiles_url
    assert_response :not_found
    post profiles_url, params: { profile: { tenant_id: @alfa.id, name: "Novo", permissions: %w[view_portfolio] } }
    assert_response :not_found
    patch profile_url(profiles(:alfa_operator)), params: { profile: { name: "X", permissions: %w[view_portfolio] } }
    assert_response :not_found

    assert_equal 3, AccessEvent.where(event: "access_denied", user: users(:carlos)).count
    assert_equal "Operador", profiles(:alfa_operator).reload.name
  end

  test "a lista traz só os perfis dos credores com a permissão 11, com os usuários de cada um (V10)" do
    sign_in_as users(:joana)

    get profiles_url

    assert_response :success
    assert_select "tbody tr", 2
    assert_select "th", text: "Credor", count: 0
    assert_select "tbody tr", text: /Operador.*3/m
    assert_select "tbody tr", text: /Gestor.*16 de 16.*1/m
  end

  test "quem gerencia perfis em dois credores vê os dois, com a coluna Credor (MT-6)" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    sign_in_as users(:ana)

    get profiles_url
    assert_select "th", text: "Credor"
    assert_select "tbody tr", 4

    get profiles_url(tenant: @beta.id)
    assert_select "tbody tr", 2
  end

  test "perfil de outro credor responde como não encontrado, por link direto, com o credor no registro (V10)" do
    sign_in_as users(:joana)

    get edit_profile_url(profiles(:beta_operator))
    assert_response :not_found
    delete profile_url(profiles(:beta_operator))
    assert_response :not_found
    post profiles_url, params: { profile: { tenant_id: @beta.id, name: "Intruso", permissions: %w[view_portfolio] } }
    assert_response :not_found

    assert Profile.exists?(profiles(:beta_operator).id)
    assert_nil Profile.find_by(name: "Intruso")
    assert_equal [ @beta.id ], AccessEvent.where(event: "access_denied", user: users(:joana)).pluck(:tenant_id).uniq
  end

  test "R30: o formulário traz as 16 permissões" do
    sign_in_as users(:joana)

    get new_profile_url

    assert_select "input[type=checkbox][name='profile[permissions][]']", 16
    assert_select "label", text: /10\. Gerenciar usuários/
  end

  test "cria o perfil Analista de carga e o atribui; o usuário vê Importar, mas não Configuração nem Usuários" do
    sign_in_as users(:joana)

    post profiles_url, params: { profile: { tenant_id: @alfa.id, name: "Analista de carga", permissions: [ "", "view_portfolio", "upload_imports" ] } }
    assert_redirected_to profiles_url
    analista = Profile.find_by!(tenant: @alfa, name: "Analista de carga")
    assert_equal %w[view_portfolio upload_imports], analista.permissions

    patch membership_profile_url(memberships(:carlos_alfa)), params: { membership: { profile_id: analista.id } }
    sign_in_as users(:carlos)
    get root_url
    assert_select "nav a", text: "Importar carteira"
    assert_select "nav a", text: "Configuração", count: 0
    assert_select "nav a", text: "Usuários", count: 0
  end

  test "R31: nome repetido no credor e PD6 voltam ao formulário com o motivo, sem gravar" do
    sign_in_as users(:joana)

    post profiles_url, params: { profile: { tenant_id: @alfa.id, name: "Gestor", permissions: %w[view_portfolio] } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Nome/

    post profiles_url, params: { profile: { tenant_id: @alfa.id, name: "Auditor", permissions: %w[manage_users] } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /consultar a carteira/
    assert_nil Profile.find_by(name: "Auditor")
  end

  test "altera um perfil (R35)" do
    sign_in_as users(:joana)

    patch profile_url(profiles(:alfa_operator)), params: { profile: { name: "Atendimento", permissions: %w[view_portfolio upload_imports] } }

    assert_redirected_to profiles_url
    assert_equal "Atendimento", profiles(:alfa_operator).reload.name
  end

  test "PD7: a gestora não muda as permissões do próprio perfil, e a recusa vem escrita" do
    sign_in_as users(:joana)

    patch profile_url(profiles(:alfa_manager)), params: { profile: { name: "Gestor", permissions: Permission::ALL - %w[manage_profiles] } }

    assert_response :unprocessable_content
    assert_select "[role=alert]", /seu próprio perfil/
    assert_equal Permission::ALL, profiles(:alfa_manager).reload.permissions
  end

  test "R41: outra pessoa não tira a gestão do perfil que mantém o credor administrável" do
    memberships(:carlos_alfa).update!(profile: Profile.create!(tenant: @alfa, name: "Só perfis", permissions: %w[view_portfolio manage_profiles]))
    sign_in_as users(:carlos)

    patch profile_url(profiles(:alfa_manager)), params: { profile: { name: "Gestor", permissions: Permission::ALL - %w[manage_profiles] } }

    assert_response :unprocessable_content
    assert_select "[role=alert]", /Ao menos um usuário ativo precisa poder gerenciar usuários e perfis/
    assert_equal Permission::ALL, profiles(:alfa_manager).reload.permissions
  end

  test "R35: apagar perfil em uso é recusado com a contagem; sem usuários, apaga" do
    sign_in_as users(:joana)

    delete profile_url(profiles(:alfa_operator))
    assert_redirected_to profiles_url
    follow_redirect!
    assert_select "[role=alert]", "Perfil em uso por 3 usuários."
    assert Profile.exists?(profiles(:alfa_operator).id)

    livre = Profile.create!(tenant: @alfa, name: "Livre", permissions: %w[view_portfolio])
    delete profile_url(livre)
    assert_redirected_to profiles_url
    assert_not Profile.exists?(livre.id)
  end
end
