# Segmentos do credor (13, R276): ver, com a permissão 4 ou 14 no credor; criar, mudar, desativar e apagar, só com a 14 (alterar políticas
# financeiras), no credor do segmento. De credor sem acesso, a resposta é "não encontrado" e a recusa fica registrada (R33). Usar o segmento no
# filtro da lista de clientes é de quem consulta (`Portfolio::Query`).
class SegmentPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("change_settings") || user.permitted_anywhere?("change_financial_policies")
  def show? = permitted?("change_settings") || permitted?("change_financial_policies")
  def create? = permitted?("change_financial_policies")
  def update? = create?
  # Apagar, só sem uso (R273); em uso, só desativar.
  def destroy? = create? && !record.used?

  class Scope < Scope
    def resolve = scope.where(tenant_id: (user.tenant_ids_with("change_settings") + user.tenant_ids_with("change_financial_policies")).uniq)
  end
end
