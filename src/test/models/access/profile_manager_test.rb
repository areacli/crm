require "test_helper"

# Perfis por credor (especificação 02): R30, R31, R35, R41, R42, PD6, PD7 e AC7.
class Access::ProfileManagerTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @manager = Access::ProfileManager.new(users(:joana))
  end

  test "R30 e R35: cria o perfil com as permissões escolhidas, na ordem da matriz, e registra" do
    profile = @manager.create(tenant: @alfa, name: " Analista de carga ", permissions: %w[confirm_imports view_portfolio upload_imports upload_imports])

    assert profile.persisted?
    assert_equal "Analista de carga", profile.name
    assert_equal %w[view_portfolio upload_imports confirm_imports], profile.permissions
    event = AccessEvent.find_by!(event: "profile_created")
    assert_equal [ @alfa.id, users(:joana).id ], [ event.tenant_id, event.actor_id ]
  end

  test "R31: o nome é único por credor, mas pode repetir em outro" do
    repetido = @manager.create(tenant: @alfa, name: "Gestor", permissions: %w[view_portfolio])
    assert_not repetido.persisted?
    assert repetido.errors[:name].any?

    assert Access::ProfileManager.new(users(:ana)).create(tenant: @beta, name: "Analista", permissions: %w[view_portfolio]).persisted?
    assert @manager.create(tenant: @alfa, name: "Analista", permissions: %w[view_portfolio]).persisted?
  end

  test "PD6 e AC7: permissão sem consultar a carteira, ou administrar acordos sem negociar, é recusada ao salvar" do
    sem_consulta = @manager.create(tenant: @alfa, name: "Sem consulta", permissions: %w[manage_users])
    assert_not sem_consulta.persisted?
    assert_includes sem_consulta.errors[:permissions], "precisa incluir consultar a carteira"

    acordos = @manager.create(tenant: @alfa, name: "Acordos", permissions: %w[view_portfolio administer_agreements])
    assert_not acordos.persisted?
    assert acordos.errors[:permissions].any?
  end

  test "permissão desconhecida é recusada" do
    assert_not @manager.create(tenant: @alfa, name: "Inventado", permissions: %w[view_portfolio inventada]).persisted?
  end

  test "R35: altera o nome e as permissões de um perfil de que o ator não faz parte, com registro do antes e do depois" do
    profile = profiles(:alfa_operator)
    @manager.update(profile, name: "Atendimento", permissions: %w[view_portfolio upload_imports])

    assert_equal "Atendimento", profile.reload.name
    assert_equal %w[view_portfolio upload_imports], profile.permissions
    event = AccessEvent.find_by!(event: "profile_updated")
    assert_equal "Operador", event.details.dig("before", "name")
    assert_equal "Atendimento", event.details.dig("after", "name")
  end

  test "alterar um perfil de um credor não altera o do outro (MT-21, R31)" do
    @manager.update(profiles(:alfa_operator), name: "Operador", permissions: %w[view_portfolio upload_imports])

    assert_equal Permission::OPERATOR, profiles(:beta_operator).reload.permissions
    assert_equal Permission::OPERATOR, Tenant.provision!("Credor novo").profiles.find_by!(name: "Operador").permissions
  end

  test "R41: tirar de um perfil as permissões 10 ou 11 que deixariam o credor sem gestão é recusado e nada muda" do
    outro = Access::ProfileManager.new(users(:carlos))
    memberships(:carlos_alfa).update!(profile: Profile.create!(tenant: @alfa, name: "Só perfis", permissions: %w[view_portfolio manage_profiles]))

    error = assert_raises(Access::Refused) { outro.update(profiles(:alfa_manager), name: "Gestor", permissions: %w[view_portfolio manage_users]) }

    assert_equal "Ao menos um usuário ativo precisa poder gerenciar usuários e perfis.", error.message
    assert_equal Permission::ALL, profiles(:alfa_manager).reload.permissions
  end

  test "PD7: ninguém muda as permissões do próprio perfil, mas pode renomeá-lo" do
    assert_raises(Access::Refused) { @manager.update(profiles(:alfa_manager), name: "Gestor", permissions: Permission::ALL - %w[change_settings]) }

    @manager.update(profiles(:alfa_manager), name: "Gestão", permissions: Permission::ALL)
    assert_equal "Gestão", profiles(:alfa_manager).reload.name
  end

  test "R35: perfil em uso não se apaga, e a mensagem diz quantos usuários o usam" do
    error = assert_raises(Access::Refused) { @manager.destroy(profiles(:alfa_operator)) }
    assert_equal "Perfil em uso por 3 usuários.", error.message

    memberships(:ana_alfa).destroy!
    memberships(:inativo_alfa).destroy!
    assert_equal "Perfil em uso por 1 usuário.", assert_raises(Access::Refused) { @manager.destroy(profiles(:alfa_operator)) }.message
  end

  test "R35: perfil sem usuários é apagado e o registro guarda quem apagou" do
    profile = @manager.create(tenant: @alfa, name: "Temporário", permissions: %w[view_portfolio])

    @manager.destroy(profile)

    assert_not Profile.exists?(profile.id)
    assert AccessEvent.exists?(event: "profile_deleted", actor: users(:joana), tenant: @alfa)
  end
end
