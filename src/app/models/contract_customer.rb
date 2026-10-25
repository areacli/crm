# Cliente de um contrato, com os papéis dele (MT-13): titular e responsável financeiro.
class ContractCustomer < ApplicationRecord
  self.primary_key = %i[contract_id customer_id]

  ROLES = %w[holder financial_responsible].freeze

  belongs_to :contract
  belongs_to :customer
end
