require "test_helper"

# Operações, etapa 1 (14, R306 a R310a): operação global, credenciamento por credor, pessoas e vínculos; o vínculo de operação só vale com o
# credenciamento ativo, sem regra em outro lugar.
class Operations::AccreditationTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @gestor = users(:joana)
  end

  test "R306: credenciar um CNPJ novo cria a operação global com o gestor dela; o mesmo CNPJ noutro credor liga à mesma operação" do
    accreditation, manager, password = Operations::Accreditor.new(@gestor).accredit(
      tenant: @alfa, cnpj: "11.444.777/0001-61", legal_name: "Recupera Cobranças Ltda", short_name: "Recupera", manager_name: "Lia", manager_email: "lia@recupera.com.br"
    )
    assert_predicate accreditation, :active?
    assert manager.operation_manager?
    assert password.present?
    assert manager.temporary_password?

    again, created, none = Operations::Accreditor.new(@gestor).accredit(tenant: @beta, cnpj: "11444777000161")
    assert_equal accreditation.operation, again.operation
    assert_nil created
    assert_nil none
    assert_equal 1, Operation.count
    assert_raises(Operations::Accreditor::Refused) { Operations::Accreditor.new(@gestor).accredit(tenant: @alfa, cnpj: "11444777000161") }
  end

  test "CNPJ inválido é recusado" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Operations::Accreditor.new(@gestor).accredit(tenant: @alfa, cnpj: "11444777000100", legal_name: "X", short_name: "X", manager_name: "Lia", manager_email: "lia@x.com.br")
    end
  end

  test "R307 e R309: a pessoa tem um perfil por credor; suspender o credenciamento num credor tira só aquele credor" do
    operation = make_operation(@alfa)
    Accreditation.create!(tenant: @beta, operation: operation)
    caio = make_operation_user(operation, @alfa)
    Membership.create!(user: caio, tenant: @beta, profile: operator_profile(@beta, permissions: %w[view_portfolio record_contact_attempts]), operation: operation)
    assert_equal [ @alfa.id, @beta.id ].sort, caio.tenant_ids_with("view_portfolio").sort
    assert_equal [ @alfa.id ], User.find(caio.id).tenant_ids_with("negotiate_agreements")

    Operations::Accreditor.new(@gestor).change_status(Accreditation.find_by(tenant: @alfa, operation: operation), "suspended", "pendência contratual")
    fresh = User.find(caio.id)
    assert_equal [ @beta.id ], fresh.tenant_ids_with("view_portfolio")
    assert_equal [ @alfa.id ], fresh.suspended_operation_tenants.pluck(:id)
    assert fresh.can_sign_in?
  end

  test "R307: encerrar o credenciamento encerra as distribuições daquele credor; reativar não as traz" do
    operation = make_operation(@alfa)
    customer = make_customer(@alfa)
    distribution = Distribution.create!(tenant: @alfa, operation: operation, customer: customer, exposure: "overdue", starts_on: Date.current)
    accreditation = Accreditation.find_by(tenant: @alfa, operation: operation)
    Operations::Accreditor.new(@gestor).change_status(accreditation, "ended", "fim do contrato")
    assert_equal "accreditation_ended", distribution.reload.end_reason
    Operations::Accreditor.new(@gestor).change_status(accreditation, "active", "volta")
    assert_predicate distribution.reload.ended_at, :present?
  end

  test "R309 e R310: o vínculo de operação exige perfil disponível para operações e a pessoa da operação" do
    operation = make_operation(@alfa)
    caio = User.create!(name: "Caio", email_address: "caio@recupera.com.br", password: "senha-de-teste-1")
    accreditation = Accreditation.find_by(tenant: @alfa, operation: operation)
    assert_raises(Operations::Accreditor::Refused) { Operations::Accreditor.new(@gestor).link(accreditation, user: caio, profile: operator_profile(@alfa)) }
    OperationMember.create!(operation: operation, user: caio)
    assert_raises(Operations::Accreditor::Refused) { Operations::Accreditor.new(@gestor).link(accreditation, user: caio, profile: profiles(:alfa_operator)) }
    membership = Operations::Accreditor.new(@gestor).link(accreditation, user: caio, profile: operator_profile(@alfa))
    assert_equal operation, membership.operation
  end

  test "OPD14: e-mail de equipe de credor não vira pessoa de operação" do
    operation = make_operation(@alfa)
    assert_raises(Operations::Accreditor::Refused) { Operations::People.new(@gestor).create_person(operation, name: "Joana", email_address: users(:joana).email_address) }
  end

  test "R310a: desativar a pessoa encerra os vínculos dela em todos os credores; a operação não fica sem gestor; o gestor sem vínculo entra" do
    operation = make_operation(@alfa)
    lia = make_operation_user(operation, @alfa, email: "lia@recupera.com.br", name: "Lia", manager: true)
    lia.memberships.update_all(active: false)
    assert User.find(lia.id).can_sign_in?, "o gestor da operação entra mesmo sem vínculo"
    caio = make_operation_user(operation, @alfa)
    people = Operations::People.new(lia)
    people.set_active(caio.operation_member, false)
    assert_not caio.memberships.first.reload.active?
    assert_not User.find(caio.id).can_sign_in?
    assert_raises(Operations::Accreditor::Refused) { people.set_manager(lia.operation_member, false) }
  end
end
