# Identidade remota do cliente (17, R407): o id que um sistema do credor dá ao cliente. O cliente continua único por credor e documento e pode ter
# várias identidades, inclusive no mesmo sistema; um mesmo id, num sistema, aponta para um único cliente.
class CustomerIdentity < ApplicationRecord
  include TenantScoped

  belongs_to :source_system
  belongs_to :customer

  normalizes :external_id, with: ->(value) { value.to_s.strip }

  validates :external_id, presence: true, length: { maximum: 100 }, uniqueness: { scope: %i[tenant_id source_system_id] }
end
