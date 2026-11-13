# Cliente de um contrato, com os papéis dele (MT-13): titular e responsável financeiro.
class ContractCustomer < ApplicationRecord
  self.primary_key = %i[contract_id customer_id]

  ROLES = %w[holder financial_responsible].freeze

  belongs_to :contract
  belongs_to :customer
  # A identidade remota usada neste contrato, a mais recente que chegou (17, R409).
  belongs_to :customer_identity, optional: true
end
