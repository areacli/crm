require "test_helper"

# Comando do administrador (R43, `bin/rails crm:user`): última saída, fora da R41.
class Access::AdminCommandTest < ActiveSupport::TestCase
  setup { @command = Access::AdminCommand.new }

  test "create: cria o usuário ligado ao credor e ao perfil, com senha temporária e registro" do
    lines = @command.run("create", "Nova@Exemplo.com.br", name: "Nova Pessoa", tenant: "Escola Alfa", profile: "Operador")

    user = User.find_by!(email_address: "nova@exemplo.com.br")
    assert_equal profiles(:alfa_operator), user.memberships.sole.profile
    assert user.temporary_password?
    assert_match(/Senha temporária/, lines.last)
    assert AccessEvent.exists?(event: "admin_user_created", user: user, tenant: tenants(:alfa), actor_id: nil)
  end

  test "create com senha definitiva: valida a R26 e não deixa a senha temporária" do
    assert_raises(Access::Refused) { @command.run("create", "b@exemplo.com.br", tenant: "Escola Alfa", password: "123456789012") }

    @command.run("create", "b@exemplo.com.br", tenant: "Escola Alfa", password: "cobranca-sem-pressa")
    assert_not User.find_by!(email_address: "b@exemplo.com.br").temporary_password?
  end

  test "create: e-mail existente, credor ou perfil inexistentes são recusados" do
    assert_equal "Usuário já existe.", assert_raises(Access::Refused) { @command.run("create", "joana@exemplo.com.br", tenant: "Escola Alfa") }.message
    assert_raises(Access::Refused) { @command.run("create", "c@exemplo.com.br", tenant: "Nenhum") }
    assert_raises(Access::Refused) { @command.run("create", "c@exemplo.com.br", tenant: "Escola Alfa", profile: "Inexistente") }
  end

  test "link: liga um usuário existente a outro credor, com o perfil dele ali (a Marta da Beta passa a Gestora da Alfa)" do
    @command.run("link", "marta@exemplo.com.br", tenant: "Escola Alfa", profile: "Gestor")

    assert_equal %w[Escola\ Alfa Clínica\ Beta].sort, users(:marta).tenants.pluck(:name).sort
    assert users(:marta).tenant_ids_with("manage_users").include?(tenants(:alfa).id)
    assert AccessEvent.exists?(event: "admin_membership_linked", user: users(:marta))
  end

  test "rename, deactivate, reactivate e reset_password" do
    @command.run("rename", "carlos@exemplo.com.br", name: "Carlos Alberto")
    assert_equal "Carlos Alberto", users(:carlos).reload.name

    users(:carlos).sessions.create!
    @command.run("deactivate", "carlos@exemplo.com.br")
    assert_not users(:carlos).reload.can_sign_in?
    assert_equal 0, users(:carlos).sessions.count

    @command.run("reactivate", "carlos@exemplo.com.br")
    assert users(:carlos).reload.can_sign_in?

    lines = @command.run("reset_password", "carlos@exemplo.com.br")
    assert users(:carlos).reload.temporary_password?
    password = lines.last[/: (\S+)\z/, 1]
    assert_equal users(:carlos), User.authenticate_by(email_address: "carlos@exemplo.com.br", password: password)
    assert_equal %w[admin_user_renamed admin_user_deactivated admin_user_reactivated admin_password_reset], AccessEvent.where(user: users(:carlos)).order(:id).pluck(:event)
  end

  test "o comando não está sujeito à R41: pode desativar a única gestora; reativar a traz de volta" do
    @command.run("deactivate", "joana@exemplo.com.br")
    @command.run("reactivate", "joana@exemplo.com.br")

    assert users(:joana).reload.can_sign_in?
  end

  test "list mostra um vínculo por linha" do
    lines = @command.run("list", nil)

    assert_includes lines, "joana@exemplo.com.br | Joana Souza | Escola Alfa | Gestor | ativo"
    assert_includes lines, "pedro@exemplo.com.br | Pedro Inativo | Escola Alfa | Operador | inativo"
  end

  test "ação desconhecida e e-mail em branco são recusados" do
    assert_raises(Access::Refused) { @command.run("apagar", "a@exemplo.com.br") }
    assert_raises(Access::Refused) { @command.run("create", " ") }
    assert_raises(Access::Refused) { @command.run("deactivate", "ninguem@exemplo.com.br") }
  end
end
