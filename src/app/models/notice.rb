# Aviso dentro do sistema (A5): quem foi ligado a um credor recebe um aviso. O sino lista os não lidos.
class Notice < ApplicationRecord
  belongs_to :user

  scope :unread, -> { where(read_at: nil) }

  after_create_commit :announce

  def read!
    update!(read_at: Time.current) unless read_at
  end

  private
    # Evento pequeno de invalidação para o sino do próprio usuário; o navegador busca a lista (decisão 0020, sem polling).
    def announce = NoticesChannel.broadcast_to(user, { event: "notice-created", notice_id: id })
end
