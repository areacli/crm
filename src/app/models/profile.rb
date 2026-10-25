# Perfil: conjunto de permissões, por credor (MT-21).
class Profile < ApplicationRecord
  belongs_to :tenant
  has_many :memberships, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :tenant_id }
  validate :permissions_are_known
  validate :permissions_have_dependencies

  def permitted?(permission) = permissions.include?(permission.to_s)

  private
    def permissions_are_known
      unknown = Array(permissions).reject { |permission| Permission.known?(permission) }
      errors.add(:permissions, :unknown, list: unknown.join(", ")) if unknown.any?
    end

    # Toda permissão exige a de consultar a carteira (PD6); administrar acordos exige negociar acordos (AC7).
    def permissions_have_dependencies
      list = Array(permissions)
      errors.add(:permissions, :needs_view_portfolio) if list.any? && !list.include?("view_portfolio")
      errors.add(:permissions, :needs_negotiate_agreements) if list.include?("administer_agreements") && !list.include?("negotiate_agreements")
    end
end
