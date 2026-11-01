# Pessoas da operação (14, R310, R310a): só o gestor da operação, e só sobre as pessoas da própria operação.
class OperationMemberPolicy < ApplicationPolicy
  def index? = user.operation_manager?
  def create? = user.operation_manager?
  def update? = user.operation_manager? && record.operation_id == user.operation&.id
  # Dar vínculo num credor: só onde o credor deixa (política "vínculos dados pelo gestor da operação", R319) e o credenciamento está ativo.
  def link?(accreditation) = update? && accreditation.active? && accreditation.operation_id == user.operation&.id &&
                             TenantSetting.where(tenant_id: accreditation.tenant_id, operation_manager_links: true).exists?

  class Scope < Scope
    def resolve = user.operation_manager? ? scope.where(operation_id: user.operation.id) : scope.none
  end
end
