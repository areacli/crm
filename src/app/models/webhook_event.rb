# Evento de webhook de pagamento recebido por um canal (identificado por canal + identificador do evento: o reenvio é inofensivo).
class WebhookEvent < ApplicationRecord
  include TenantScoped

  belongs_to :channel, class_name: "PaymentChannel"

  enum :status, { received: "received", applied: "applied", ignored: "ignored", rejected: "rejected", failed: "failed" }, validate: true
end
