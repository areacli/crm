module DistributionRules
  # Confirmação de uma mudança do enquadramento da distribuição (14, R345): recusa a conferência velha, troca os itens, sobe a versão, registra
  # e recalcula em segundo plano.
  class Applier
    def initialize(actor) = @actor = actor

    def confirm(tenant, token)
      proposal = Proposal.from_token(tenant, token).validate!
      ApplicationRecord.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant.id)
        raise Distributions::Refused, I18n.t("distribution_rules.stale") if setting.distribution_rules_version != proposal.version

        before = describe(Proposal.current(tenant))
        DistributionRuleItem.where(tenant: tenant, active: true).update_all(active: false, updated_at: Time.current)
        proposal.items.each_with_index do |item, index|
          DistributionRuleItem.create!(tenant: tenant, segment_id: item.segment_id, operation_ids: item.operation_ids, exposure: item.exposure, position: index + 1)
        end
        setting.update!(distribution_rules_version: setting.distribution_rules_version + 1)
        Change.record!(setting, "distribution_rules_changed", tenant_id: tenant.id, actor: @actor, origin: "screen", before: before, after: describe(proposal))
      end
      DistributionRulesJob.perform_later(tenant, @actor)
    end

    private
      def describe(proposal)
        names = Operation.where(id: proposal.items.flat_map(&:operation_ids)).pluck(:id, :short_name).to_h
        segments = Segment.where(id: proposal.items.map(&:segment_id)).pluck(:id, :name).to_h
        proposal.items.each_with_index.map { |item, index| "#{index + 1}. #{segments[item.segment_id]} → #{item.operation_ids.map { names[_1] }.join(', ')} (#{item.exposure})" }.join("; ").presence || "vazio"
      end
  end
end
