# Acordos (11, R245, R245a): as permissões 16 (negociar acordos) e 17 (administrar acordos) valem no credor do acordo (MT-3), e a lista, a ficha e as ações
# respondem "não encontrado" a quem não as tem, com a recusa registrada (R33). Aprovar e recusar exigem os limites atuais de quem aprova cobrirem a proposta, e
# nunca valem para quem a montou (R216). Cancelar e aceitar valem para qualquer usuário com a 16 (DA33, ACD1).
class AgreementPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("negotiate_agreements")
  def show? = negotiates?
  def watch? = negotiates?
  def create? = negotiates?
  def accept? = negotiates? && record.state_approved?
  def cancel? = negotiates? && record.proposal?
  def term? = show?

  # Calcular a quitação: acordo ativo, ou quebrado na forma "parcelas seguem" (R230).
  def settle? = negotiates? && !record.reversing? && (%w[active_on_time active_late].include?(record.state) || (record.state_broken? && record.break_form == "installments_follow"))

  # Quebra manual e arquivo de acordos: "administrar acordos" no credor (R238, R244, R245).
  def break? = administers? && !record.reversing? && %w[awaiting_effectuation active_on_time active_late].include?(record.state)
  def export? = administers?

  # Reverter (cancelar) o acordo aceito, em dois passos, e desistir (R239): "administrar acordos" no credor.
  def revert? = administers? && Agreements::Reversion::REVERTIBLE.include?(record.state) && !record.reversing?
  def conclude? = administers? && record.reversing?
  alias_method :desist?, :conclude?

  # Aprovar e recusar a proposta pendente: a 16 no credor, limites atuais que a cobririam, e nunca quem a montou (R216).
  def approve?
    record.state_pending? && record.user_id != user.id && negotiates? && Agreements::Limits.user_covers?(user, record)
  end
  alias_method :refuse?, :approve?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("negotiate_agreements"))
  end

  private
    def administers? = permitted?("administer_agreements") && permitted?("view_portfolio")

    def negotiates? = permitted?("negotiate_agreements") && permitted?("view_portfolio")
end
