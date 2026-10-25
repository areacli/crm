# Tela de índices (08, R147, R157, R158): ver, com a permissão 1, 4 ou 14 (pelo endereço, quem só consulta); corrigir e buscar agora, com a 14,
# no credor cuja configuração está aberta. O registro é o credor (ou a correção dele).
class IndexPolicy < ApplicationPolicy
  def show? = %w[view_portfolio change_settings change_financial_policies].any? { |permission| user.permitted_anywhere?(permission) }
  def correct? = permitted?("change_financial_policies")
  def search? = user.permitted_anywhere?("change_financial_policies")
end
