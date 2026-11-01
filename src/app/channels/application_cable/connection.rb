module ApplicationCable
  # Uma conexão por aba. Quando há sessão válida, `current_user` vem do cookie assinado da sessão; sem sessão a conexão não é
  # rejeitada aqui: cada canal decide quem pode assinar (a plataforma é pública, os canais de credor e de usuário não).
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    # Cada assinatura e cada mensagem declaram o papel do banco de quem está conectado (decisão 0024): um usuário de operação só assina o canal
    # de um cliente que está pra ele.
    around_command { |_, block| Operations::Context.for_user(current_user, &block) }

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
