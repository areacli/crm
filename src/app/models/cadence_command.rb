# Comando (21, R436, R441): uma ação para um destinatário, com um item por objeto, posto na fila do executor do tipo. O estado é o resumo dos
# itens: na fila enquanto algum item está na fila. O executor reserva o comando (`claimed_at`) antes de agir, porque a fila entrega ao menos uma vez.
class CadenceCommand < ApplicationRecord
  include TenantScoped

  STATES = { queued: "queued", executed: "executed", failed: "failed", no_return: "no_return", discarded: "discarded" }.freeze

  belongs_to :round, class_name: "CadenceRound", foreign_key: :cadence_round_id, inverse_of: :commands
  belongs_to :action, class_name: "CadenceAction", foreign_key: :cadence_action_id
  belongs_to :recipient, class_name: "Customer", foreign_key: :recipient_customer_id, optional: true
  has_many :items, class_name: "CadenceCommandItem", dependent: :delete_all, inverse_of: :command

  enum :state, STATES, validate: true
end
