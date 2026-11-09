# Entrada e saída. A mesma mensagem para usuário inexistente, senha errada, bloqueio e acesso recusado (não revela quem existe).
class SessionsController < ApplicationController
  # Serve página ou arquivo direto, fora da casca (impressão, download, entrada).
  skip_before_action :redirect_page_to_shell
  allow_unauthenticated_access only: %i[ new create ]
  skip_before_action :require_password_change, only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { spa? ? render(json: { erro: t("sessions.too_many") }, status: :too_many_requests) : redirect_to(root_path, alert: t("sessions.too_many")) }

  # A entrada é a da casca (fase 8): o endereço antigo leva à raiz, que mostra o formulário quando não há sessão.
  def new = redirect_to(root_path)

  def create
    email_address = params[:email_address].to_s.strip.downcase
    candidate = User.find_by(email_address: email_address)

    # R27: bloqueado, nem a senha certa entra até o prazo passar.
    return refuse(email_address, candidate, "login_locked") if candidate&.locked?

    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.can_sign_in?
      start_new_session_for user
      AccessEvent.record("login", request: request, user: user)
      # 14, R308: o credor que suspendeu a operação some do acesso, com o aviso; o gestor da operação sem carteira vai às pessoas dela.
      suspended = user.suspended_operation_tenants.order(:name).pluck(:name)
      flash[:alert] = t("operations.sign_in.suspended", operation: user.operation.short_name, tenants: suspended.to_sentence) if suspended.any? && user.operation
      return head(:no_content) if spa?
      return redirect_to(operation_people_path) if user.operation_manager? && !user.permitted_anywhere?("view_portfolio")

      redirect_to after_authentication_url
    elsif user&.operation && user.active?
      # Senha certa, mas nenhum credor ativo para a operação (credenciamentos suspensos ou encerrados): a mensagem diz isso, não "inválido".
      AccessEvent.record("login_refused", request: request, user: user, email_address: email_address)
      suspended = user.suspended_operation_tenants.order(:name).pluck(:name)
      message = suspended.any? ? t("operations.sign_in.suspended", operation: user.operation.short_name, tenants: suspended.to_sentence) : t("operations.sign_in.none_active", operation: user.operation.short_name)
      return render(json: { erro: message }, status: :unauthorized) if spa?

      redirect_to root_path, alert: message
    else
      blocked = candidate.present? && user.nil? && candidate.register_failed_login!
      AccessEvent.record("account_locked", request: request, user: candidate, details: { minutes: User::LOCK_FOR.in_minutes.to_i }) if blocked
      refuse(email_address, candidate, "login_refused")
    end
  end

  def destroy
    AccessEvent.record("logout", request: request, user: Current.user)
    # 15, R354: sair encerra a entrega aberta do usuário.
    QueueDelivery.open.where(user_id: Current.user.id).find_each { |delivery| delivery.finish!("signed_out") }
    terminate_session
    return head(:no_content) if spa?

    redirect_to root_path, status: :see_other
  end

  private
    def refuse(email_address, candidate, event)
      AccessEvent.record(event, request: request, user: candidate, email_address: email_address.presence)
      return render(json: { erro: t("sessions.invalid") }, status: :unauthorized) if spa?

      redirect_to root_path, alert: t("sessions.invalid")
    end
end
