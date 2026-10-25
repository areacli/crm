# Transferência de crédito entre contratos (R55a): a permissão 17 (administrar acordos), no credor dos contratos. O registro é o contrato
# de origem.
class CreditTransferPolicy < ApplicationPolicy
  def create? = permitted?("administer_agreements")
end
