# Entrega (15, R353, R354): o sujeito que um operador recebeu pelo "Próximo", travado para ele até se encerrar. Os índices únicos parciais
# garantem uma entrega aberta por sujeito e uma por operador.
class QueueDelivery < ApplicationRecord
  include TenantScoped

  END_REASONS = %w[recorded returned expired released signed_out].freeze

  belongs_to :work_queue
  belongs_to :user
  belongs_to :released_by, class_name: "User", optional: true

  validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true

  scope :open, -> { where(ended_at: nil) }

  def subject_record = subject == "contracts" ? Contract.find_by(id: subject_id) : Customer.find_by(id: subject_id)

  def customer_ids = subject == "contracts" ? ContractCustomer.where(contract_id: subject_id).pluck(:customer_id) : [ subject_id ]

  def finish!(reason, by: nil) = update!(ended_at: Time.current, end_reason: reason, released_by: by)
end
