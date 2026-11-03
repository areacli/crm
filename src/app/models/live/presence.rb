# Quem está com a SPA aberta (decisão 0025): um contador por usuário no cache (Valkey em produção), uma unidade por conexão. Expira sozinho
# depois de 12 horas, para uma conexão que caiu sem `unsubscribed` não deixar o usuário "presente" para sempre.
module Live
  module Presence
    TTL = 12.hours

    module_function

    def key(user_id) = "live:presenca:#{user_id}"

    def enter(user)
      Rails.cache.increment(key(user.id), 1, expires_in: TTL) || Rails.cache.write(key(user.id), 1, expires_in: TTL, raw: true)
    end

    def leave(user)
      Rails.cache.delete(key(user.id)) if Rails.cache.decrement(key(user.id), 1).to_i <= 0
    end

    def present?(user_id) = Rails.cache.read(key(user_id), raw: true).to_i.positive?

    def present_user_ids(user_ids) = user_ids.select { |id| present?(id) }
  end
end
