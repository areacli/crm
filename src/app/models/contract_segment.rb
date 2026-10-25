# Histórico de segmento do contrato (R153, PO-2, PO-12): uma linha por mudança, com o dia em que valeu. Segmento vazio é "sem segmento".
# Não guarda dado pessoal e continua depois da anonimização do cliente.
class ContractSegment < ApplicationRecord
  belongs_to :contract
  belongs_to :segment, optional: true
end
