# Contrato: obrigatório para todo título (MT-11), com um ou mais clientes do mesmo credor (MT-12). Sem código quando criado por
# omissão (MT-14).
class Contract < ApplicationRecord
  include TenantScoped

  belongs_to :segment, optional: true
  has_many :contract_segments, dependent: :delete_all
  has_many :contract_customers, dependent: :destroy
  has_many :customers, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error
  has_many :credits, dependent: :restrict_with_error

  # Crédito do contrato (R55b): a soma do livro; é do contrato, não de um cliente.
  def credit_cents = credits.sum(:amount_cents)

  def label = code.presence || "Contrato sem código"
end
