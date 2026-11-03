# Fila (15, R349, R350): item do enquadramento da fila de um credor, de clientes ou de contratos. Leva um segmento (menos a trilha padrão), a
# ordem, a trava e os intervalos; um item "sem fila" (`delivers: false`) não entrega a ninguém. Vale o primeiro item cujo segmento casar.
class WorkQueue < ApplicationRecord
  include TenantScoped

  SUBJECTS = %w[customers contracts].freeze
  # Critérios de ordem (R355): coluna calculada no recálculo; os vazios vão para o fim.
  ORDERS = %w[overdue_balance overdue_days without_contact return_at broken_promise].freeze
  RESULT_INTERVALS = { "talked_to_customer" => :interval_customer_minutes, "talked_to_third_party" => :interval_third_party_minutes,
                       "no_contact" => :interval_no_contact_minutes }.freeze

  belongs_to :segment, optional: true
  has_many :queue_group_queues, dependent: :destroy
  has_many :groups, through: :queue_group_queues, source: :queue_group

  validates :subject, inclusion: { in: SUBJECTS }
  validates :name, presence: true, length: { maximum: 100 }
  validates :order_by, inclusion: { in: ORDERS }
  validates :order_tiebreak, inclusion: { in: ORDERS }, allow_nil: true
  validates :lock_minutes, numericality: { only_integer: true, in: 1..240 }
  validates :interval_no_contact_minutes, :interval_third_party_minutes, :interval_customer_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { where(active: true).order(:catch_all, :position, :id) }

  # A trilha padrão de cada sujeito nasce "sem fila" (R349) e é criada na primeira vez que alguém a pede.
  def self.catch_all_for(tenant, subject)
    find_by(tenant: tenant, subject: subject, catch_all: true) || find_or_create_by!(tenant: tenant, subject: subject, catch_all: true) { |queue| queue.assign_attributes(name: I18n.t("queues.catch_all"), delivers: false) }
  rescue ActiveRecord::RecordNotUnique
    find_by!(tenant: tenant, subject: subject, catch_all: true)
  end

  # O enquadramento de um sujeito em ordem, com a trilha padrão no fim.
  def self.framing(tenant, subject)
    catch_all_for(tenant, subject)
    where(tenant: tenant, subject: subject).ordered.includes(:segment).to_a
  end

  def interval_after(result_kind) = public_send(RESULT_INTERVALS.fetch(result_kind.to_s, :interval_no_contact_minutes)).minutes
end
