require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "criar um credor traz a configuração inicial e os perfis Gestor e Operador (MT-21)" do
    tenant = Tenant.provision!("Academia Gama")

    assert_equal 6, tenant.setting.aging_brackets.size
    assert_equal %w[Gestor Operador], tenant.profiles.order(:name).pluck(:name)
    assert_equal Permission::ALL, tenant.profiles.find_by!(name: "Gestor").permissions
    assert_equal Permission::OPERATOR, tenant.profiles.find_by!(name: "Operador").permissions
  end

  test "R396: o credor nasce com os sistemas CRM e Planilha, de chave natural e ativos" do
    tenant = Tenant.provision!("Academia Gama")

    assert_equal [ %w[CRM crm natural active], %w[Planilha default natural active] ], tenant.source_systems.order(:name).pluck(:name, :role, :key_kind, :status)
    assert_equal "last_sender", tenant.setting.customer_record_policy
  end

  test "o vínculo exige perfil do mesmo credor" do
    membership = Membership.new(user: users(:sem_vinculo), tenant: tenants(:alfa), profile: profiles(:beta_manager))

    assert_not membership.valid?
    assert_includes membership.errors[:profile], "é de outro credor"
  end
end
