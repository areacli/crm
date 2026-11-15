# As rodadas das réguas de um credor num horário (21, R435, R436), na fila `cadences`: decidir, priorizar, montar e enfileirar, em passos que se
# retomam de onde pararam. Cada passo também grava a sua marca na rodada, então um job novo do despachante para a mesma hora continua dali.
class CadenceRoundJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :cadences
  discard_on ActiveJob::DeserializationError
  # Outra rodada da mesma régua em andamento: esta espera (21, "Casos de exceção").
  retry_on Cadences::Round::Busy, wait: 30.seconds, attempts: 40

  def perform(tenant, scheduled_for)
    round = Cadences::Round.new(tenant, Time.zone.parse(scheduled_for.to_s))
    step(:decide) { round.decide }
    step(:prioritize) { round.prioritize }
    step(:build) { round.build }
    step(:enqueue) { |enqueue| round.enqueue(enqueue) }
  end
end
