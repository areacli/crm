# Segmentos do credor (08, R157, R158): ver, com a permissão 4 ou 14; mudar, só com a 14 (alterar políticas financeiras), no credor do segmento.
# O "Demais" não se edita. De credor sem acesso, a resposta é "não encontrado" e a recusa fica registrada (R33).
class SegmentPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("change_settings") || user.permitted_anywhere?("change_financial_policies")
  def create? = permitted?("change_financial_policies")
  # O "Demais" não tem critérios, mas tem regra de encargos: a edição dele só mexe nela (09, R160).
  def update? = create?

  # Mover, desativar e reativar: o "Demais" fica sempre por último e ativo (R149).
  def rearrange? = create? && !record.catch_all?

  # Mudar ordem, política e situação, sobre a lista do credor (o registro é o credor ou um segmento dele).
  def manage? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: (user.tenant_ids_with("change_settings") + user.tenant_ids_with("change_financial_policies")).uniq)
  end
end
