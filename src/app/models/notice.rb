# Aviso dentro do sistema (A5): quem foi ligado a um credor recebe um aviso. O sino lista os não lidos.
class Notice < ApplicationRecord
  belongs_to :user

  scope :unread, -> { where(read_at: nil) }
end
