# Sessão do navegador (gerador de autenticação do Rails 8). Vale 8 horas desde a entrada (R28).
class Session < ApplicationRecord
  LIFETIME = 8.hours

  belongs_to :user

  def expired? = created_at < LIFETIME.ago
end
