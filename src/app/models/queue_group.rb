# Grupo (15, R353, R358): usuários de um credor ligados a filas, em ordem. Um grupo não mistura operações, nem usuários de operação com a
# equipe do credor.
class QueueGroup < ApplicationRecord
  include TenantScoped

  has_many :queue_group_users, dependent: :delete_all
  has_many :users, through: :queue_group_users
  has_many :queue_group_queues, -> { order(:position) }, dependent: :delete_all
  has_many :work_queues, through: :queue_group_queues

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validate :one_side

  private
    # R358: todos da mesma operação, ou todos da equipe do credor.
    def one_side
      sides = Membership.where(tenant_id: tenant_id, user_id: users.map(&:id)).pluck(:operation_id).uniq
      errors.add(:users, I18n.t("queues.groups.mixed")) if sides.size > 1
    end
end
