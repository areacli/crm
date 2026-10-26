module Segments
  # Confirmação da mudança de segmentos (R154, DS3): vale na hora. Recusa a conferência velha (dois gestores ao mesmo tempo), grava os
  # segmentos e a política, registra cada alteração com quem, quando, antes e depois (R156), sobe a versão e recalcula os contratos.
  class Applier
    def initialize(user) = @user = user

    def confirm(tenant, token)
      proposal = Proposal.from_token(tenant, token)
      ApplicationRecord.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant.id)
        raise Refused, I18n.t("segments.errors.stale") if setting.segments_version != proposal.version

        save_segments(tenant, proposal)
        if setting.segment_product_policy != proposal.policy
          log("tenant_setting", setting.id, "updated", "segment_product_policy", setting.segment_product_policy, proposal.policy, tenant)
          setting.segment_product_policy = proposal.policy
        end
        save_charges(tenant, setting, proposal)
        setting.segments_version += 1
        setting.save!
        tenant.association(:setting).reset
        # 09, AN1: a regra efetiva de cada segmento fica guardada com a data da mudança; o encargo até um pagamento segue a regra vigente nele.
        Charges::RuleHistory.record!(tenant)
        Recalculation.new(tenant).apply
      end
      Broadcast.changed(tenant)
      # 09, R163, R173: a regra nova vale já, para todos os títulos em aberto; o recálculo roda em segundo plano, em até 2 minutos.
      ValuesRecalculationJob.enqueue_for(tenant, reason: "encargos")
    end

    private
      def save_segments(tenant, proposal)
        position = 0
        proposal.entries.each do |entry|
          segment = entry[:id].to_i.positive? ? Segment.find_by!(id: entry[:id], tenant_id: tenant.id) : Segment.new(tenant: tenant)
          before = segment.attributes.slice(*tracked)
          segment.position = entry[:catch_all] ? 0 : (position += 1)
          segment.assign_attributes(entry.slice(:name, :active, *Segment::CRITERIA, *Segment::CHARGE_FIELDS))
          segment.save!
          if segment.previously_new_record?
            log("segment", segment.id, "created", nil, nil, segment.name, tenant)
          else
            segment.attributes.slice(*tracked).each do |field, after|
              next if before[field] == after

              log("segment", segment.id, field == "active" ? (after ? "reactivated" : "deactivated") : "updated", field, before[field].to_s, after.to_s, tenant)
            end
          end
        end
      end

      # Parâmetros e políticas de encargos do credor (09, R160, R163, R180 a R182): registra cada campo que mudou, com antes e depois (R156).
      def save_charges(tenant, setting, proposal)
        setting.assign_attributes(proposal.charges.slice(*TenantSetting::CHARGE_FIELDS))
        setting.changes.slice(*TenantSetting::CHARGE_FIELDS).each do |field, (before, after)|
          log("tenant_setting", setting.id, "updated", field, before.to_s, after.to_s, tenant)
        end
      end

      def tracked = %w[name position active] + Segment::CRITERIA.map(&:to_s) + Segment::CHARGE_FIELDS.map(&:to_s)

      def log(type, id, event, field, before, after, tenant)
        Change.record!(tenant_id: tenant.id, user: @user, subject_type: type, subject_id: id, event: event, field: field, before: before, after: after, origin: "screen")
      end
  end
end
