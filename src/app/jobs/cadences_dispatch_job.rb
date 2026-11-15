# Despachante das réguas (21, R435, R437), a cada minuto. O cron só vê o minuto em que está: as horas previstas vêm da agenda de cada régua, e a
# que passou sem rodada é criada aqui (atrasada no mesmo dia; "falhou" nos dias anteriores, até 7 dias para trás). Enfileira um job por credor e
# horário, e de novo o que ficou parado no meio, para a retomada. A régua com a vigência acabada fica desligada, com o motivo.
class CadencesDispatchJob < ApplicationJob
  queue_as :cadences

  LOOKBACK_DAYS = 7
  REDISPATCH_AFTER = 30.minutes

  def perform(now = Time.current)
    now = Time.zone.parse(now.to_s) unless now.is_a?(ActiveSupport::TimeWithZone)
    today = now.to_date
    Operations::Context.system do
      Cadence.joins(:tenant).where(enabled: true, tenants: { active: true }).find_each do |cadence|
        next if expire(cadence, today)

        plan(cadence, now, today)
      end
      fail_unstarted(today)
      dispatch(now)
    end
  end

  private
    # R437: vigência encerrada desliga a régua, com o motivo e o registro.
    def expire(cadence, today)
      return false unless cadence.valid_until && cadence.valid_until < today

      cadence.update!(enabled: false, disabled_reason: "vigência encerrada")
      Change.record!(cadence, "disabled", tenant_id: cadence.tenant_id, field: "enabled", before: "true", after: "false", note: "vigência encerrada")
      true
    end

    # As horas previstas de hoje até agora e as dos dias anteriores, desde que a régua foi ligada.
    def plan(cadence, now, today)
      (today - LOOKBACK_DAYS..today).each do |day|
        slot = Cadences::Schedule.slot(cadence, day)
        next if slot.nil? || slot > now
        next if cadence.enabled_since && slot < cadence.enabled_since

        attributes = if day < today then { state: "failed", failure: "não rodou no dia", finished_at: now }
        else { state: "scheduled", late: now - slot > Cadences::Round::LATE_AFTER }
        end
        CadenceRound.insert_all([ { tenant_id: cadence.tenant_id, cadence_id: cadence.id, scheduled_for: slot, created_at: now, updated_at: now }.merge(attributes) ],
                                unique_by: %i[cadence_id scheduled_for])
      end
    end

    # A rodada que não começou até a meia-noite fica "falhou" (R435); a que começou é retomada pela decisão gravada.
    def fail_unstarted(today)
      CadenceRound.where(state: "scheduled", started_at: nil).where(scheduled_for: ...today.beginning_of_day)
                  .update_all(state: "failed", failure: "não rodou no dia", finished_at: Time.current, updated_at: Time.current)
    end

    # Um job por credor e horário; o parado há mais de 30 minutos vai de novo (os passos se retomam pela marca de cada rodada).
    def dispatch(now)
      pending = CadenceRound.open.where(scheduled_for: now.beginning_of_day..now)
                            .where("dispatched_at is null or (dispatched_at < ? and finished_at is null)", now - REDISPATCH_AFTER)
      pending.distinct.pluck(:tenant_id, :scheduled_for).each do |tenant_id, slot|
        CadenceRoundJob.perform_later(Tenant.find(tenant_id), slot.iso8601)
      end
      pending.update_all(dispatched_at: now, updated_at: now)
    end
end
