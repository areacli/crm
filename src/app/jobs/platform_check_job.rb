# Verificação da plataforma: roda numa fila do Sidekiq e transmite um sinal pelo Action Cable. Um job por fila prova, de ponta
# a ponta, Valkey, Sidekiq e WebSocket.
class PlatformCheckJob < ApplicationJob
  QUEUES = %w[imports exports messaging webhooks default].freeze

  def perform(queue_name)
    ActionCable.server.broadcast(PlatformChannel::STREAM, { event: "platform-ping", queue: queue_name, sent_at: Time.current.iso8601 })
  end
end
