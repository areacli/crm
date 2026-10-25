# Contrato: obrigatório para todo título (MT-11), com um ou mais clientes do mesmo credor (MT-12). Sem código quando criado por
# omissão (MT-14).
class Contract < ApplicationRecord
  include TenantScoped

  has_many :contract_customers, dependent: :destroy
  has_many :customers, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error

  def label = code.presence || "Contrato sem código"
end
