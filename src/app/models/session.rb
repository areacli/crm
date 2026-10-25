# Sessão do navegador (gerador de autenticação do Rails 8). Vale 8 horas desde a entrada e acaba antes se ficar 30 minutos sem atividade (R28).
# A atividade é a última vez que `updated_at` foi tocado; o toque é limitado a um por minuto, para não gravar a cada pedido.
class Session < ApplicationRecord
  LIFETIME = 8.hours
  IDLE_TIMEOUT = 30.minutes
  TOUCH_EVERY = 1.minute

  belongs_to :user

  def expired? = created_at < LIFETIME.ago || updated_at < IDLE_TIMEOUT.ago

  # Registra a atividade desta requisição (R28).
  def record_activity! = (touch if updated_at < TOUCH_EVERY.ago)
end
