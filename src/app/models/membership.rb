# Vínculo usuário × credor × perfil (MT-2). A permissão é conferida no credor do registro (MT-3).
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :tenant
  belongs_to :profile

  validates :user_id, uniqueness: { scope: :tenant_id }
  validate :profile_belongs_to_tenant

  scope :active, -> { where(active: true) }

  # Nome e senha são da pessoa, não do vínculo (R36a): quem gerencia um credor só os altera de quem não tem vínculo em outro credor.
  def personal_data_editable? = !Membership.where(user_id: user_id).where.not(tenant_id: tenant_id).exists?

  private
    def profile_belongs_to_tenant
      errors.add(:profile, :other_tenant) if profile && tenant_id != profile.tenant_id
    end
end
