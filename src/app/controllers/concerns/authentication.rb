# Autenticação por sessão (gerador do Rails 8), com a sessão de 8 horas e 30 minutos de inatividade (R28). `Current.user` é o usuário da sessão.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # A sessão vencida (8 horas, ou 30 minutos sem atividade) ou de usuário que deixou de poder entrar é encerrada na hora (R28, R30).
    def find_session_by_cookie
      session = Session.includes(:user).find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
      return session&.tap(&:record_activity!) unless session && (session.expired? || !session.user.can_sign_in?)

      session.destroy
      cookies.delete(:session_id)
      nil
    end

    def request_authentication
      # A SPA recebe 401 e abre a entrada por cima das abas, sem perder o que está nelas (decisão 0028).
      return head(:unauthorized) if spa?

      redirect_to root_path
    end

    # A entrada é a da casca (fase 8): quem entra pelo envio sem a SPA vai à raiz, que abre a casca.
    def after_authentication_url = root_url

    def start_new_session_for(user)
      user.register_successful_login!
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
