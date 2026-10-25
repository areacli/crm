require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "recusa permissão desconhecida" do
    profile = Profile.new(tenant: tenants(:alfa), name: "Novo", permissions: %w[view_portfolio inventada])

    assert_not profile.valid?
    assert_includes profile.errors[:permissions].join, "inventada"
  end

  test "toda permissão exige consultar a carteira (PD6)" do
    profile = Profile.new(tenant: tenants(:alfa), name: "Novo", permissions: %w[manage_users])

    assert_not profile.valid?
    assert_includes profile.errors[:permissions], "precisa incluir consultar a carteira"
  end

  test "administrar acordos exige negociar acordos (AC7)" do
    profile = Profile.new(tenant: tenants(:alfa), name: "Novo", permissions: %w[view_portfolio administer_agreements])

    assert_not profile.valid?
    assert_includes profile.errors[:permissions].join, "negociar acordos"
  end

  test "o nome é único por credor, mas pode repetir em outro" do
    assert_not Profile.new(tenant: tenants(:alfa), name: "Gestor", permissions: Permission::ALL).valid?
    assert Profile.new(tenant: tenants(:alfa), name: "Auditor", permissions: %w[view_portfolio]).valid?
  end

  test "as 17 permissões têm número e texto em português" do
    assert_equal 17, Permission::ALL.size
    assert_equal 10, Permission.number("manage_users")
    assert_equal "Gerenciar usuários", Permission.label("manage_users")
  end

  test "não apaga perfil com usuários" do
    assert_not profiles(:alfa_operator).destroy
    assert Profile.exists?(profiles(:alfa_operator).id)
  end
end
