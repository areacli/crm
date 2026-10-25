# Cliente (antes "devedor"): único por credor, pelo documento (MT-9). Anonimizado (07), perde nome e documento e segue como participante
# anônimo dos contratos (R132a); retido (R138), não é anonimizado pela tarefa diária até a retenção ser desfeita.
class Customer < ApplicationRecord
  include TenantScoped

  has_many :contract_customers, dependent: :destroy
  has_many :contracts, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error
  has_many :contact_attempts, dependent: :restrict_with_error
  has_many :contacts, class_name: "CustomerContact", dependent: :destroy
  belongs_to :retained_by, class_name: "User", optional: true

  scope :identified, -> { where(anonymized_at: nil) }
  scope :retained, -> { where.not(retained_at: nil) }

  def anonymized? = anonymized_at.present?
  def retained? = retained_at.present?

  def masked_document = anonymized? ? "—" : Document.mask(document)
  def formatted_document = anonymized? ? "—" : Document.format(document)
end
