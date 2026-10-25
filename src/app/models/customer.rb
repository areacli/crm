# Cliente (antes "devedor"): único por credor, pelo documento (MT-9).
class Customer < ApplicationRecord
  include TenantScoped

  has_many :contract_customers, dependent: :destroy
  has_many :contracts, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error
  has_many :contact_attempts, dependent: :restrict_with_error
  has_many :contacts, class_name: "CustomerContact", dependent: :destroy

  def masked_document = Document.mask(document)
  def formatted_document = Document.format(document)
end
