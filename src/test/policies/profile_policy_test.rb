require "test_helper"

# Isolamento por credor (V10): ninguém vê nem mexe em perfil de credor em que não tem a permissão 11.
class ProfilePolicyTest < ActiveSupport::TestCase
  test "o gestor da Alfa vê e altera os perfis da Alfa, não os da Beta" do
    joana = users(:joana)

    assert_equal Profile.where(tenant: tenants(:alfa)).pluck(:id).sort, ProfilePolicy::Scope.new(joana, Profile).resolve.pluck(:id).sort
    assert ProfilePolicy.new(joana, profiles(:alfa_operator)).update?
    assert_not ProfilePolicy.new(joana, profiles(:beta_operator)).update?
  end

  test "a Ana, gestora só na Beta, vê só os perfis da Beta" do
    resolvidos = ProfilePolicy::Scope.new(users(:ana), Profile).resolve

    assert_equal [ tenants(:beta).id ], resolvidos.pluck(:tenant_id).uniq
  end

  test "o operador não gerencia perfis" do
    carlos = users(:carlos)

    assert_not ProfilePolicy.new(carlos, Profile).index?
    assert_empty ProfilePolicy::Scope.new(carlos, Profile).resolve
    assert_not ProfilePolicy.new(carlos, profiles(:alfa_operator)).show?
  end

  test "apagar perfil é da permissão 11 no credor dele; perfil em uso é recusado pelo gerenciador (R35)" do
    assert ProfilePolicy.new(users(:joana), profiles(:alfa_operator)).destroy?
    assert_not ProfilePolicy.new(users(:joana), profiles(:beta_operator)).destroy?
  end

  test "o usuário não altera o próprio vínculo (R33)" do
    joana_alfa = memberships(:joana_alfa)

    assert_not MembershipPolicy.new(users(:joana), joana_alfa).update?
    assert MembershipPolicy.new(users(:joana), memberships(:carlos_alfa)).update?
    assert_not MembershipPolicy.new(users(:joana), memberships(:ana_beta)).update?
  end
end
