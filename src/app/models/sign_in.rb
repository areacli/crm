# Tentativa de entrada, usada pela API. A mesma mensagem para usuário inexistente, senha errada, bloqueio e acesso recusado (não revela quem existe).
class SignIn
  # `user`: quem entrou, ou nil. `alert`: a mensagem da recusa ou, para quem entrou, o aviso do credor que suspendeu a operação (14, R308).
  Result = Data.define(:user, :alert)

  def initialize(email_address:, password:, request:)
    @email_address = email_address.to_s.strip.downcase
    @raw_email_address = email_address
    @password = password
    @request = request
  end

  def call
    candidate = User.find_by(email_address: @email_address)
    # R27: bloqueado, nem a senha certa entra até o prazo passar.
    return refuse(candidate, "login_locked") if candidate&.locked?

    user = User.authenticate_by(email_address: @raw_email_address.to_s, password: @password.to_s)
    if user&.can_sign_in?
      Result.new(user: user, alert: suspended_notice(user))
    elsif user&.operation && user.active?
      # Senha certa, mas nenhum credor ativo para a operação (credenciamentos suspensos ou encerrados): a mensagem diz isso, não "inválido".
      AccessEvent.record("login_refused", request: @request, user: user, email_address: @email_address)
      Result.new(user: nil, alert: suspended_notice(user) || I18n.t("operations.sign_in.none_active", operation: user.operation.short_name))
    else
      blocked = candidate.present? && user.nil? && candidate.register_failed_login!
      AccessEvent.record("account_locked", request: @request, user: candidate, details: { minutes: User::LOCK_FOR.in_minutes.to_i }) if blocked
      refuse(candidate, "login_refused")
    end
  end

  private
    def refuse(candidate, event)
      AccessEvent.record(event, request: @request, user: candidate, email_address: @email_address.presence)
      Result.new(user: nil, alert: I18n.t("sessions.invalid"))
    end

    def suspended_notice(user)
      return unless user.operation

      suspended = user.suspended_operation_tenants.order(:name).pluck(:name)
      I18n.t("operations.sign_in.suspended", operation: user.operation.short_name, tenants: suspended.to_sentence) if suspended.any?
    end
end
