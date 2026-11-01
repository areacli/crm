# Item do enquadramento da distribuição (14, R342): um segmento de contratos, as operações que recebem quem casa e a exposição. Vale o primeiro
# item cujo segmento o contrato atende; quem não casa fica com a equipe do credor (a trilha padrão, sem item).
class DistributionRuleItem < ApplicationRecord
  include TenantScoped
  belongs_to :segment

  validates :exposure, inclusion: { in: Distribution::EXPOSURES }
  scope :active, -> { where(active: true) }
  scope :ordered, -> { active.order(:position, :id) }

  def operations = Operation.where(id: operation_ids).order(:short_name)
end
