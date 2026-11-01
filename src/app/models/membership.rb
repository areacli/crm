# Vínculo usuário × credor × perfil (MT-2). A permissão é conferida no credor do registro (MT-3).
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :tenant
  belongs_to :profile
  # Operação (14, R309): vazio é a equipe do credor; preenchido, o usuário é da operação e só alcança o que está pra ela (R313).
  belongs_to :operation, optional: true

  validates :user_id, uniqueness: { scope: :tenant_id }
  validate :profile_belongs_to_tenant
  validate :operation_matches_user

  scope :active, -> { where(active: true) }
  # Vínculo que vale agora (14, R307): ativo e, se for de operação, com a operação ativa, o credenciamento dela ativo no credor e a pessoa
  # ativa na operação. Credenciamento suspenso ou encerrado tira todas as permissões do vínculo naquele credor, sem regra em outro lugar.
  scope :usable, -> {
    active.where(<<~SQL)
      memberships.operation_id IS NULL OR EXISTS (
        SELECT 1 FROM accreditations a JOIN operations o ON o.id = a.operation_id JOIN operation_members m ON m.operation_id = a.operation_id
         WHERE a.tenant_id = memberships.tenant_id AND a.operation_id = memberships.operation_id AND a.status = 'active'
           AND o.active AND m.user_id = memberships.user_id AND m.active)
    SQL
  }

  # Nome e senha são da pessoa, não do vínculo (R36a): quem gerencia um credor só os altera de quem não tem vínculo em outro credor.
  def personal_data_editable? = !Membership.where(user_id: user_id).where.not(tenant_id: tenant_id).exists?

  def operation? = operation_id.present?

  private
    # O vínculo de operação é da operação da pessoa, num credor que a credencia, com perfil disponível para operações (R309, R310).
    def operation_matches_user
      return unless operation_id

      member = OperationMember.find_by(user_id: user_id)
      errors.add(:operation, :not_member) unless member&.operation_id == operation_id
      errors.add(:operation, :not_accredited) unless Accreditation.exists?(tenant_id: tenant_id, operation_id: operation_id)
      errors.add(:profile, :not_for_operations) if profile && !profile.available_to_operations?
    end

    def profile_belongs_to_tenant
      errors.add(:profile, :other_tenant) if profile && tenant_id != profile.tenant_id
    end
end
