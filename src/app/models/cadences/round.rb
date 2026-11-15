module Cadences
  # As rodadas de um credor num horário (21, R435, R436): correm juntas, em ordem de prioridade, em quatro passos que se retomam de onde pararam
  # (o job `CadenceRoundJob` é contínuo, e cada passo grava a sua marca). A falha de uma régua fica na rodada dela e não para as outras.
  class Round
    # Outra rodada da mesma régua ainda em andamento (agenda mudada no meio): esta espera (21, "Casos de exceção").
    class Busy < StandardError; end

    LOCK = 7
    # Depois de quanto a rodada conta como atrasada (R435): roda no mesmo dia, depois da hora.
    LATE_AFTER = 5.minutes

    def initialize(tenant, scheduled_for)
      @tenant = tenant
      @scheduled_for = scheduled_for
    end

    def rounds
      CadenceRound.where(tenant_id: @tenant.id, scheduled_for: @scheduled_for).where.not(state: "failed")
                  .joins(:cadence).includes(:cadence).order("cadences.position", "cadences.id").to_a
    end

    # Decidir (R434, R435): uma transação por régua, com a trava da régua; a régua já decidida é pulada na retomada.
    def decide
      rounds.each do |round|
        next if round.decided_at

        decide_one(round)
      end
    end

    # Priorizar (R436): entre as rodadas do horário, depois que todas decidiram.
    def prioritize
      pending = rounds.select { |round| round.decided_at && round.prioritized_at.nil? }
      return if pending.empty?

      ApplicationRecord.transaction do
        Commands.prioritize(rounds.select(&:decided_at).map(&:id))
        CadenceRound.where(id: pending.map(&:id)).update_all(prioritized_at: Time.current, updated_at: Time.current)
      end
    end

    # Montar os comandos de cada régua, com os disparos.
    def build
      rounds.each do |round|
        next if round.built_at || round.decided_at.nil? || round.prioritized_at.nil?

        ApplicationRecord.transaction do
          Commands.build(round)
          round.update!(built_at: Time.current)
        end
      end
    end

    # Pôr na fila e encerrar as rodadas do horário.
    def enqueue(step = nil)
      built = rounds.select(&:built_at)
      Commands.enqueue(built.map(&:id)) { |last_id| step&.set!(last_id) }
      # O cursor é só atalho: a fonte da verdade é `enqueued_at` de cada comando.
      built.each do |round|
        next if round.finished?

        round.update!(state: round.summary["lane_error"] ? "completed_with_failures" : "completed", finished_at: Time.current)
      end
    end

    private
      def decide_one(round)
        ApplicationRecord.transaction do
          Portfolio::Sql.execute("select pg_advisory_xact_lock(?, ?)", LOCK, round.cadence_id)
          round.reload
          next if round.decided_at

          raise Busy if CadenceRound.where(cadence_id: round.cadence_id, state: "running").where.not(id: round.id).exists?

          cadence = round.cadence
          unless cadence.enabled? && cadence.valid_on?(round.day)
            round.update!(state: "failed", failure: cadence.enabled? ? "fora da vigência" : "régua desligada antes da rodada", finished_at: Time.current)
            next
          end
          now = Time.current
          round.update!(state: "running", started_at: round.started_at || now, late: round.late || now - round.scheduled_for > LATE_AFTER,
                        data_as_of: DataAsOf.for(@tenant))
          Portfolio::Sql.execute("set local work_mem = '#{Segments::Compiler::WORK_MEM}'")
          result = Decision.new(round).call
          round.update!(summary: result.summary, decided_at: Time.current)
        end
      rescue Busy
        raise
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id, cadence_round_id: round.id })
        round.reload.update!(state: "failed", failure: "erro ao decidir (#{error.class.name.demodulize})", finished_at: Time.current)
      end
  end
end
