# Um comando da régua na fila do executor do tipo (21, R438 a R440, R447), na fila `cadences`. Leva só o id: o estado está na tabela, e o executor
# reserva o comando antes de agir, porque a fila entrega ao menos uma vez.
class CadenceCommandJob < ApplicationJob
  queue_as :cadences

  def perform(command_id)
    command = CadenceCommand.find_by(id: command_id)
    Cadences::Executors.run(command) if command
  end
end
