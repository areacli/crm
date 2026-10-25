require "test_helper"

# Gestão de usuários pela tela (especificação 02): R32, R36, R36a, R37, R40, R41, R42 e PD7, sempre por credor.
class Access::UserManagerTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @joana = users(:joana)                  # única gestora (10 e 11) da Alfa
    @manager = Access::UserManager.new(@joana)
  end

  test "R36 e R37: cria o usuário ligado ao credor, com senha temporária de 72 horas, e registra sem a senha" do
    user, password = @manager.create(tenant: @alfa, email_address: "Nova.Pessoa@Exemplo.com.br", name: " Nova Pessoa ", profile: profiles(:alfa_operator))

    assert_equal "nova.pessoa@exemplo.com.br", user.email_address
    assert_equal "Nova Pessoa", user.name
    assert_match(/\A[a-zA-Z2-9]{4}(-[a-zA-Z2-9]{4}){3}\z/, password)
    assert_equal user, User.authenticate_by(email_address: user.email_address, password: password)
    assert_in_delta 72.hours.from_now, user.temporary_password_until, 5
    assert_equal profiles(:alfa_operator), user.memberships.sole.profile

    event = AccessEvent.find_by!(event: "user_created", user: user)
    assert_equal [ @alfa.id, @joana.id ], [ event.tenant_id, event.actor_id ]
    assert_equal({ "profile" => "Operador" }, event.details)
    assert_not_includes AccessEvent.pluck(:details).to_json, password
  end

  test "a senha temporária tem 16 caracteres em quatro grupos e a senha de cada criação é outra" do
    senhas = Array.new(5) { Access::TemporaryPassword.generate }

    senhas.each { |senha| assert_equal 19, senha.length }
    assert_equal 5, senhas.uniq.size
  end

  test "R36: o e-mail repetido, em qualquer grafia, não cria um segundo usuário" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @manager.create(tenant: @alfa, email_address: "CARLOS@exemplo.com.br", name: "Outro Carlos", profile: profiles(:alfa_operator))
    end
    assert_equal 1, User.where(email_address: "carlos@exemplo.com.br").count
  end

  test "o perfil precisa ser do credor" do
    assert_raises(Access::Refused) { @manager.create(tenant: @alfa, email_address: "x@exemplo.com.br", name: "X", profile: profiles(:beta_operator)) }
    assert_raises(Access::Refused) { @manager.change_profile(memberships(:carlos_alfa), profiles(:beta_manager)) }
  end

  test "R36a: liga quem já existe em outro credor, na hora, com aviso a ele e registro" do
    assert_difference -> { Notice.count } => 1 do
      @manager.link(tenant: @alfa, user: users(:marta), profile: profiles(:alfa_manager))
    end

    membership = Membership.find_by!(user: users(:marta), tenant: @alfa)
    assert membership.active?
    assert_equal profiles(:alfa_manager), membership.profile
    assert users(:marta).reload.tenant_ids_with("manage_users").include?(@alfa.id)
    notice = users(:marta).notices.sole
    assert_equal "linked_to_tenant", notice.kind
    assert_equal({ "tenant_name" => "Escola Alfa", "actor_name" => "Joana Souza", "profile_name" => "Gestor" }, notice.data)
    assert AccessEvent.exists?(event: "membership_linked", user: users(:marta), tenant: @alfa, actor: @joana)
    assert_equal 1, users(:marta).memberships.where(tenant: @beta).count, "o vínculo da Beta não muda"
  end

  test "R36a: ligar quem já está ativo no credor é recusado; quem estava desativado é reativado com o novo perfil" do
    assert_raises(Access::Refused) { @manager.link(tenant: @alfa, user: users(:carlos), profile: profiles(:alfa_manager)) }

    memberships(:carlos_alfa).update!(active: false)
    @manager.link(tenant: @alfa, user: users(:carlos), profile: profiles(:alfa_manager))

    assert memberships(:carlos_alfa).reload.active?
    assert_equal profiles(:alfa_manager), memberships(:carlos_alfa).profile
  end

  test "R36a: usuário desativado no sistema não é ligado pela tela" do
    assert_raises(Access::Refused) { @manager.link(tenant: @alfa, user: users(:inativo), profile: profiles(:alfa_operator)) }
  end

  test "R32: muda o perfil do vínculo e registra o antes e o depois" do
    @manager.change_profile(memberships(:carlos_alfa), profiles(:alfa_manager))

    assert_equal profiles(:alfa_manager), memberships(:carlos_alfa).reload.profile
    event = AccessEvent.find_by!(event: "profile_changed", user: users(:carlos))
    assert_equal({ "before" => "Operador", "after" => "Gestor" }, event.details)
  end

  test "PD7: ninguém muda o próprio perfil, nem desativa a própria conta, nem redefine a própria senha" do
    assert_raises(Access::Refused) { @manager.change_profile(memberships(:joana_alfa), profiles(:alfa_operator)) }
    assert_raises(Access::Refused) { @manager.set_active(memberships(:joana_alfa), false) }
    assert_raises(Access::Refused) { @manager.reset_password(memberships(:joana_alfa)) }
    assert_equal profiles(:alfa_manager), memberships(:joana_alfa).reload.profile
  end

  test "R41: outra pessoa não consegue tirar a última gestão do credor, por perfil nem por desativação" do
    admin_de_usuarios = Profile.create!(tenant: @alfa, name: "Só usuários", permissions: %w[view_portfolio manage_users])
    memberships(:carlos_alfa).update!(profile: admin_de_usuarios)
    outro = Access::UserManager.new(users(:carlos))

    assert_raises(Access::Refused) { outro.change_profile(memberships(:joana_alfa), profiles(:alfa_operator)) }
    error = assert_raises(Access::Refused) { outro.set_active(memberships(:joana_alfa), false) }
    assert_equal "Ao menos um usuário ativo precisa poder gerenciar usuários e perfis.", error.message
    assert_equal profiles(:alfa_manager), memberships(:joana_alfa).reload.profile
    assert memberships(:joana_alfa).active?
  end

  test "R41 é por credor: gerir a Beta não cobre a falta de gestão na Alfa, e na Beta com outro gestor a mesma mudança vale" do
    # Ana gerencia a Beta; na Alfa a única gestora é a Joana, e a Ana (com a 10) tenta tirá-la.
    memberships(:ana_alfa).update!(profile: Profile.create!(tenant: @alfa, name: "Só usuários", permissions: %w[view_portfolio manage_users]))
    ana = Access::UserManager.new(users(:ana))

    assert_raises(Access::Refused) { ana.set_active(memberships(:joana_alfa), false) }

    # Na Beta, com um segundo gestor, o perfil da Ana pode mudar (feito pelo outro gestor).
    memberships(:marta_beta).update!(profile: profiles(:beta_manager))
    Access::UserManager.new(users(:marta)).change_profile(memberships(:ana_beta), profiles(:beta_operator))
    assert_equal profiles(:beta_operator), memberships(:ana_beta).reload.profile
  end

  test "R41 conta só vínculo ativo de usuário ativo" do
    memberships(:ana_alfa).update!(profile: Profile.create!(tenant: @alfa, name: "Só usuários", permissions: %w[view_portfolio manage_users]))
    users(:joana).update!(active: false)

    assert_raises(Access::Refused) { Access::Guard.ensure_manager_remains!(@alfa.id) }
  end

  test "R40: desativar o vínculo na Alfa não tira a Ana da Beta; reativar volta" do
    @manager.set_active(memberships(:ana_alfa), false)

    assert_not memberships(:ana_alfa).reload.active?
    assert users(:ana).reload.can_sign_in?
    assert_equal [ @beta.id ], users(:ana).tenant_ids_with("manage_users")
    assert AccessEvent.exists?(event: "membership_deactivated", user: users(:ana), tenant: @alfa)

    @manager.set_active(memberships(:ana_alfa), true)
    assert memberships(:ana_alfa).reload.active?
    assert AccessEvent.exists?(event: "membership_reactivated", user: users(:ana), tenant: @alfa)
  end

  test "R40: sem nenhum vínculo ativo, o usuário deixa de poder entrar" do
    @manager.set_active(memberships(:carlos_alfa), false)

    assert_not users(:carlos).reload.can_sign_in?
  end

  test "R36 (revisão 3): altera o nome de quem só atua neste credor, com registro" do
    @manager.rename(memberships(:carlos_alfa), "Carlos Alberto Lima")

    assert_equal "Carlos Alberto Lima", users(:carlos).reload.name
    assert_equal({ "before" => "Carlos Lima", "after" => "Carlos Alberto Lima" }, AccessEvent.find_by!(event: "user_renamed").details)
  end

  test "R36a: nome e senha de quem atua em outro credor não se alteram por aqui" do
    # A Ana tem vínculo na Alfa e na Beta; a Joana, da Alfa, não altera o nome nem redefine a senha dela.
    assert_raises(Access::Refused) { @manager.rename(memberships(:ana_alfa), "Outro Nome") }
    assert_raises(Access::Refused) { @manager.reset_password(memberships(:ana_alfa)) }
    assert_equal "Ana Prado", users(:ana).reload.name
  end

  test "R37: redefinir a senha gera outra temporária, zera o bloqueio, encerra as sessões e a anterior deixa de valer" do
    users(:carlos).update!(failed_attempts: 3, locked_until: 10.minutes.from_now)
    users(:carlos).sessions.create!

    password = @manager.reset_password(memberships(:carlos_alfa))

    carlos = users(:carlos).reload
    assert_nil User.authenticate_by(email_address: carlos.email_address, password: "senha-de-teste-1")
    assert_equal carlos, User.authenticate_by(email_address: carlos.email_address, password: password)
    assert carlos.temporary_password?
    assert_not carlos.locked?
    assert_equal 0, carlos.sessions.count
    assert_equal "password_reset", AccessEvent.where(user: carlos).order(:id).last.event
    assert_not_includes AccessEvent.pluck(:details).to_json, password
  end
end
