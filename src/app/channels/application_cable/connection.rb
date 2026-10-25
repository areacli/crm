module ApplicationCable
  # Uma conexão por aba. Quando há sessão válida, `current_user` vem do cookie assinado da sessão; sem sessão a conexão não é
  # rejeitada aqui: cada canal decide quem pode assinar (a plataforma é pública, os canais de credor e de usuário não).
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_user_by_session
    end

    private
      def find_user_by_session
        session = Session.includes(:user).find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
        session.user if session && !session.expired? && session.user.can_sign_in?
      end
  end
end
