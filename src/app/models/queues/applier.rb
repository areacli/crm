module Queues
  # Confirmação de uma mudança do enquadramento da fila (15, R357): recusa a conferência velha, atualiza as filas que continuam (posição,
  # segmento, nome, "sem fila"), cria as novas e desativa as que saíram, sobe a versão, registra e recalcula em segundo plano.
  class Applier
    def initialize(actor) = @actor = actor

    def confirm(tenant, token)
      proposal = Proposal.from_token(tenant, token).validate!
      ApplicationRecord.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant.id)
        raise Refused, I18n.t("queues.stale") if setting.queue_rules_version != proposal.version

        before = describe(Proposal.current(tenant, proposal.subject))
        kept = []
        proposal.items.each_with_index do |item, index|
          queue = item.id ? WorkQueue.find_by!(tenant: tenant, id: item.id) : WorkQueue.new(tenant: tenant, subject: proposal.subject)
          queue.update!(segment_id: item.segment_id, name: item.name, delivers: item.delivers, position: index + 1, active: true)
          kept << queue.id
        end
        WorkQueue.where(tenant: tenant, subject: proposal.subject, catch_all: false, active: true).where.not(id: kept).update_all(active: false, updated_at: Time.current)
        setting.update!(queue_rules_version: setting.queue_rules_version + 1)
        Change.record!(setting, "queue_rules_changed", tenant_id: tenant.id, actor: @actor, origin: "screen", before: before, after: describe(proposal))
      end
      QueuesJob.perform_later(tenant)
    end

    private
      def describe(proposal)
        list = proposal.items.each_with_index.map { |item, index| "#{index + 1}. #{item.name}#{' (sem fila)' unless item.delivers}" }
        "#{I18n.t("queues.subjects.#{proposal.subject}")}: #{list.join('; ').presence || 'vazio'}"
      end
  end
end
