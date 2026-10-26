# Entrada e saída. A mesma mensagem para usuário inexistente, senha errada, bloqueio e acesso recusado (não revela quem existe).
class SessionsController < ApplicationController
  layout "entrada"
  allow_unauthenticated_access only: %i[ new create ]
  skip_before_action :require_password_change, only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.too_many") }

  def new
  end

  def create
    email_address = params[:email_address].to_s.strip.downcase
    candidate = User.find_by(email_address: email_address)

    # R27: bloqueado, nem a senha certa entra até o prazo passar.
    return refuse(email_address, candidate, "login_locked") if candidate&.locked?

    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.can_sign_in?
      start_new_session_for user
      AccessEvent.record("login", request: request, user: user)
      redirect_to after_authentication_url
    else
      blocked = candidate.present? && user.nil? && candidate.register_failed_login!
      AccessEvent.record("account_locked", request: request, user: candidate, details: { minutes: User::LOCK_FOR.in_minutes.to_i }) if blocked
      refuse(email_address, candidate, "login_refused")
    end
  end

  def destroy
    AccessEvent.record("logout", request: request, user: Current.user)
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private
    def refuse(email_address, candidate, event)
      AccessEvent.record(event, request: request, user: candidate, email_address: email_address.presence)
      redirect_to new_session_path, alert: t("sessions.invalid")
    end
end
