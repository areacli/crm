# Distribuição (14, R311): o credor entrega um cliente ou um contrato a uma operação credenciada, com a exposição e o período. Cliente ou
# contrato é só a forma de escolher; o que muda é a pergunta "está pra mim?" (R313, `Operations::Reach`).
class Distribution < ApplicationRecord
  include TenantScoped
  belongs_to :operation
  belongs_to :customer, optional: true
  belongs_to :contract, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  EXPOSURES = %w[overdue all].freeze
  END_REASONS = %w[period_end operation_contract performance contested deceased customer_request other accreditation_ended left_segment manual_override].freeze
  # Motivos que o gestor escolhe ao recolher (R311); os outros são do sistema.
  RECALL_REASONS = %w[operation_contract performance contested deceased customer_request other].freeze
  SOURCES = %w[manual batch rule].freeze

  validates :exposure, inclusion: { in: EXPOSURES }
  validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true
  validate :customer_or_contract

  scope :open, -> { where(ended_at: nil) }
  # Vale hoje (dia de Brasília): aberta, já começou e não passou do fim (R311).
  scope :in_force, ->(on = Date.current) { open.where("starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?)", on, on) }

  def target = customer || contract
  def target_label = customer ? "cliente #{customer.name}" : "contrato #{contract.code}"
  def agendada? = ended_at.nil? && starts_on > Date.current
  def status_key = ended_at ? "ended" : (agendada? ? "scheduled" : (ends_on && ends_on < Date.current ? "ended" : "in_force"))

  private
    def customer_or_contract
      errors.add(:base, :customer_or_contract) unless customer_id.present? ^ contract_id.present?
    end
end
