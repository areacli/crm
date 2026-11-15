module Cadences
  # O contrato do executor (21, R438 a R440, R447): reservar o comando, perguntar "ainda vale?", executar os itens que valem e devolver o retorno de
  # cada um. A mensageria e os outros executores, quando existirem, cumprem o mesmo contrato. Nesta versão só a emissão é real; os outros tipos
  # são simulados (RG21: "receber, executar, retornar, a gente moca por enquanto").
  module Executors
    module_function

    BATCH = 500

    # O job de um comando reserva um lote de comandos da mesma rodada e do mesmo tipo ainda livres (o dele entre eles, se ainda livre) e responde
    # "ainda vale?" por todos de uma vez; os jobs dos outros comandos do lote, quando chegarem, não acham nada a fazer. `now`: a hora da pergunta
    # (a recriação da demonstração executa as rodadas dos dias anteriores na hora de cada uma).
    def run(command, now: Time.current)
      commands = claim(command)
      return if commands.empty?

      valid = StillValid.batch(commands, now: now)
      commands.each do |each_command|
        items = valid.fetch(each_command.id, [])
        for_kind(each_command.kind).call(each_command, items) if items.any?
        Returns.refresh_command(each_command)
      end
    end

    # A fila entrega ao menos uma vez: cada comando é reservado por um job só (`for update skip locked` e a condição `claimed_at is null`).
    def claim(command)
      ids = CadenceCommand.transaction do
        candidates = CadenceCommand.where(cadence_round_id: command.cadence_round_id, kind: command.kind, claimed_at: nil)
        first = candidates.where(id: command.id).lock("for update skip locked").pluck(:id)
        others = candidates.where.not(id: command.id).order(:id).limit(BATCH - first.size).lock("for update skip locked").pluck(:id)
        chosen = first + others
        CadenceCommand.where(id: chosen).update_all(claimed_at: Time.current, updated_at: Time.current) if chosen.any?
        chosen
      end
      CadenceCommand.where(id: ids).includes(:action, round: :cadence).order(:id).to_a
    end

    def for_kind(kind) = kind.to_s == "issue_instrument" ? IssueInstrument : Simulated

    # R440: registra o que faria e devolve "executado" em cada item; nada sai do CRM nem muda a carteira.
    module Simulated
      module_function

      def call(command, items)
        action = command.action
        items.each do |item|
          Returns.executed(item, I18n.t("cadences.simulated", action: Labels.action(action), target: Labels.object(item.decision)))
        end
      end
    end

    # R447: a emissão real, pelo ponto único da emissão (16), com o objeto e o "reemitir" do parâmetro. O que a 16 recusa volta como falhou.
    module IssueInstrument
      module_function

      def call(command, items)
        action = command.action
        items.each do |item|
          result = Instruments::Request.for_cadence(item.decision, action)
          if result.issued.any?
            Returns.record(item, "executed", detail: result.detail, payment_instrument: result.issued.first)
          else
            Returns.failed(item, result.reason)
          end
        end
      end
    end
  end
end
