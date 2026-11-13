require "test_helper"

# Identidade remota do cliente (17, R407 a R409): o id do cliente em cada sistema, e a identidade usada na ligação com o contrato.
class CustomerIdentityTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @erp = SourceSystem.create!(tenant: @alfa, name: "ERP Escolar", key_kind: "own_id")
    @billing = SourceSystem.create!(tenant: @alfa, name: "Faturamento", key_kind: "own_id")
    @ana = make_customer(@alfa, document: FakeData.cpf(101), name: "Ana Lima", contract_code: "C-7")
    @bia = make_customer(@alfa, document: FakeData.cpf(102), name: "Bia Rocha", contract_code: "C-20")
  end

  test "R407: o cliente tem várias identidades, inclusive no mesmo sistema" do
    @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: " A-1 ")
    @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: "A-2")
    @ana.identities.create!(tenant: @alfa, source_system: @billing, external_id: "A-1")

    assert_equal %w[A-1 A-1 A-2], @ana.identities.order(:external_id).pluck(:external_id)
  end

  test "R407: um id, num sistema, aponta para um único cliente" do
    @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: "A-1")
    repeated = @bia.identities.build(tenant: @alfa, source_system: @erp, external_id: "A-1")

    assert_not repeated.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      CustomerIdentity.insert_all!([ { tenant_id: @alfa.id, source_system_id: @erp.id, customer_id: @bia.id, external_id: "A-1" } ])
    end
  end

  test "R409: a ligação guarda a identidade usada, e apagar a identidade não apaga a ligação" do
    identity = @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: "A-1")
    link = ContractCustomer.find_by!(customer: @ana)
    link.update!(customer_identity: identity)

    identity.destroy!

    assert_nil link.reload.customer_identity_id
  end

  test "sistema com identidade não é excluído; excluir o cliente leva as identidades" do
    @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: "A-1")

    assert_not @erp.destroy
    assert_raises(ActiveRecord::StatementInvalid) { SourceSystem.transaction(requires_new: true) { SourceSystem.where(id: @erp.id).delete_all } }
    @ana.identities.destroy_all
    assert @erp.reload.destroy
  end

  test "0024: a operação só lê a identidade do cliente que está pra ela" do
    operation = make_operation(@alfa)
    caio = make_operation_user(operation, @alfa)
    mine = @ana.identities.create!(tenant: @alfa, source_system: @erp, external_id: "A-1")
    @bia.identities.create!(tenant: @alfa, source_system: @erp, external_id: "B-1")
    Distribution.create!(tenant: @alfa, operation: operation, customer: @ana, exposure: "all", starts_on: Date.current - 1)
    Operations::ReachBuilder.new(@alfa).rebuild

    Operations::Context.for_user(caio) { assert_equal [ mine.id ], CustomerIdentity.where(tenant: @alfa).pluck(:id) }
    Operations::Context.for_user(users(:joana)) { assert_equal 2, CustomerIdentity.where(tenant: @alfa).count }
  end
end
