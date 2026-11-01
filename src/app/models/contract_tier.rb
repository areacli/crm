# Histórico do enquadramento financeiro do contrato (13, R268; PO-12): uma linha por mudança, com o dia em que valeu. Item vazio é "sem
# enquadramento". É a base do acúmulo de encargos por período (09, R171). Não guarda dado pessoal e continua depois da anonimização do cliente.
class ContractTier < ApplicationRecord
  belongs_to :contract
  belongs_to :tier, optional: true
end
