# Operações (14): credenciar uma operação num credor, com pessoas e vínculos, para os testes.
module OperationsTestHelper
  OPERATION_CNPJ = "11444777000161".freeze

  def operator_profile(tenant, permissions: %w[view_portfolio record_contact_attempts negotiate_agreements])
    tenant.profiles.find_by(name: "Operador de operação") || tenant.profiles.create!(name: "Operador de operação", permissions: permissions, available_to_operations: true)
  end

  # Operação credenciada no credor, com uma pessoa vinculada (e-mail e nome dados) e o gestor da operação sem vínculo.
  def make_operation(tenant, short_name: "Recupera", cnpj: OPERATION_CNPJ)
    operation = Operation.find_by(cnpj: cnpj) || Operation.create!(cnpj: cnpj, legal_name: "#{short_name} Cobranças Ltda", short_name: short_name)
    Accreditation.find_or_create_by!(tenant: tenant, operation: operation)
    operation
  end

  def make_operation_user(operation, tenant, email: "caio@recupera.com.br", name: "Caio", manager: false, profile: operator_profile(tenant))
    user = User.find_by(email_address: email) || User.create!(name: name, email_address: email, password: "senha-de-teste-1")
    OperationMember.find_or_create_by!(operation: operation, user: user) { |member| member.manager = manager }
    Membership.create!(user: user, tenant: tenant, profile: profile, operation: operation) unless Membership.exists?(user: user, tenant: tenant)
    user
  end
end
