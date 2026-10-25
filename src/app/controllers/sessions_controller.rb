# Entrada e saída. A mesma mensagem para usuário inexistente, senha errada e acesso recusado (não revela quem existe).
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.too_many") }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))

    if user&.can_sign_in?
      start_new_session_for user
      AccessEvent.record("login", request: request, user: user)
      redirect_to after_authentication_url
    else
      AccessEvent.record("login_refused", request: request, email_address: params[:email_address].to_s.strip.downcase.presence)
      redirect_to new_session_path, alert: t("sessions.invalid")
    end
  end

  def destroy
    AccessEvent.record("logout", request: request, user: Current.user)
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
