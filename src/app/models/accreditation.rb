# Credenciamento (14, R307): a ligação entre um credor e uma operação que o atende. Suspenso, os usuários da operação perdem o acesso a este
# credor e as distribuições ficam; encerrado, perdem o acesso e as distribuições deste credor se encerram. Um credor não afeta outro.
class Accreditation < ApplicationRecord
  include TenantScoped
  belongs_to :operation

  enum :status, { active: "active", suspended: "suspended", ended: "ended" }, validate: true

  validates :operation_id, uniqueness: { scope: :tenant_id }
end
