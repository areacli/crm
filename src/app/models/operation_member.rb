# Pessoa da operação (14, R309, R310): o usuário pertence a uma operação só; em cada credor que ela atende, tem um vínculo com um perfil
# daquele credor. O gestor da operação cuida das pessoas dela, uma vez para todos os credores (R310a).
class OperationMember < ApplicationRecord
  belongs_to :operation
  belongs_to :user

  validates :user_id, uniqueness: true

  scope :active, -> { where(active: true) }
end
