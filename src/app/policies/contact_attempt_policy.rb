# Acionamentos (R76): a permissão vale no credor do registro (MT-3). Registrar exige a 7 e a 1 (RP1); não há anulação (revisão 5). Acionamento de credor sem acesso responde como "não encontrado" e a recusa fica registrada (R33).
class ContactAttemptPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("view_portfolio")
  # Ver o histórico de um cliente (e acompanhar o credor pelo WebSocket): consultar a carteira no credor.
  def show? = permitted?("view_portfolio")
  def watch? = show?
  def create? = permitted?("record_contact_attempts") && permitted?("view_portfolio")
  class Scope < Scope
    def resolve = scope.visible_to(user, "view_portfolio")
  end
end
