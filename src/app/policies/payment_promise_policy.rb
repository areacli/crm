# Promessas (10): a permissão vale no credor da promessa (MT-3). Aprovar e recusar exigem a 7 (registrar acionamentos) e a alçada que cobriria a
# promessa, e nunca vale para quem a registrou (R192); cancelar exige a 15 (R200). Promessa de credor sem acesso responde como "não encontrado"
# e a recusa fica registrada (R33).
class PaymentPromisePolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("record_contact_attempts")
  def show? = permitted?("view_portfolio")
  def watch? = show?

  # Registrar a promessa é registrar o acionamento (7 e 1, RP1).
  def create? = permitted?("record_contact_attempts") && permitted?("view_portfolio")

  # Aprovar e recusar a promessa pendente: a 7, a alçada que cobriria o prazo pedido, e nunca quem a registrou (R192).
  def approve?
    record.state_pending? && record.user_id != user.id && permitted?("record_contact_attempts") && permitted?("view_portfolio") &&
      Promises::Limits.covers?(user, record)
  end
  alias_method :refuse?, :approve?

  # Cancelar a promessa aberta ou pendente: a 15 (R200).
  def cancel? = record.holding? && permitted?("cancel_payment_promises") && permitted?("view_portfolio")

  class Scope < Scope
    def resolve = scope.visible_to(user, "view_portfolio")
  end
end
