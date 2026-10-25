# Resumo da carteira: quem consulta a carteira em algum credor (permissão 1); mostra só os credores dele (MT-5).
class SummaryPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("view_portfolio")
end
