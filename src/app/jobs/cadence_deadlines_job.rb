# Sem retorno (21, R439, R437a), a cada 10 minutos: o item ainda na fila depois do prazo do tipo na régua passa a "sem retorno" e aparece como
# alerta na rodada; o retorno que chegar depois ainda vale (`Cadences::Returns`).
class CadenceDeadlinesJob < ApplicationJob
  queue_as :cadences

  def perform(now = Time.current)
    Operations::Context.system do
      CadenceCommand.where(state: "queued").where(deadline_at: ...now).find_each do |command|
        command.items.where(state: "queued").update_all(state: "no_return", updated_at: now)
        Cadences::Returns.refresh_command(command)
      end
    end
  end
end
