# Item do comando (21, R438, R439, R441): um objeto do comando, com o retorno dele. Na fila → executado | falhou (motivo) | sem retorno (que ainda
# recebe o retorno que chegar); descartado quando o executor pergunta "ainda vale?" e não vale mais.
class CadenceCommandItem < ApplicationRecord
  belongs_to :command, class_name: "CadenceCommand", foreign_key: :cadence_command_id, inverse_of: :items
  belongs_to :decision, class_name: "CadenceDecision", foreign_key: :cadence_decision_id
  belongs_to :contract, optional: true
  belongs_to :customer, optional: true
  belongs_to :bill, optional: true
  belongs_to :payment_instrument, optional: true

  enum :state, CadenceCommand::STATES, validate: true
end
