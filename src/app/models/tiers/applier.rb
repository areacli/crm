module Tiers
  # Confirmação de uma mudança no enquadramento financeiro ou num segmento usado nele (13, R272, DS3): vale na hora. Recusa a conferência velha
  # (dois gestores ao mesmo tempo), grava os segmentos mudados, os itens e os parâmetros do credor, registra cada alteração com quem, quando,
  # antes e depois (R274; o segmento pelo texto curto), sobe a versão e recalcula os contratos.
  class Applier
    def initialize(user) = @user = user

    def confirm(tenant, token)
      proposal = Proposal.from_token(tenant, token)
      ApplicationRecord.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant.id)
        raise Refused, I18n.t("tiers.errors.stale") if setting.tiers_version != proposal.version

        save_segments(tenant, proposal)
        save_tiers(tenant, proposal)
        save_charges(tenant, setting, proposal)
        setting.tiers_version += 1
        setting.save!
        tenant.association(:setting).reset
        # 09, AN1: a regra efetiva de cada item fica guardada com a data da mudança; o encargo até um pagamento segue a regra vigente nele.
        Charges::RuleHistory.record!(tenant)
        Recalculation.new(tenant).apply
      end
      Broadcast.changed(tenant)
      # 09, R163, R173: a regra nova vale já, para todos os títulos em aberto; o recálculo roda em segundo plano, em até 2 minutos.
      ValuesRecalculationJob.enqueue_for(tenant, reason: "encargos")
    end

    private
      def save_segments(tenant, proposal)
        proposal.segments.each do |id, changes|
          segment = Segment.find_by!(id: id, tenant_id: tenant.id)
          before_text = segment.text.short_text
          before = segment.attributes.slice("name", "active")
          segment.update!(changes.slice("name", "expression", "active"))
          log("segment", segment.id, "updated", "expression", before_text, segment.text.short_text, tenant) if before_text != segment.text.short_text
          before.each do |field, value|
            next if segment[field] == value

            log("segment", segment.id, field == "active" ? (segment.active ? "reactivated" : "deactivated") : "updated", field, value.to_s, segment[field].to_s, tenant)
          end
        end
      end

      def save_tiers(tenant, proposal)
        position = 0
        proposal.entries.each do |entry|
          tier = entry[:id].to_i.positive? ? Tier.find_by!(id: entry[:id], tenant_id: tenant.id) : Tier.new(tenant: tenant, kind: "financial", segment_id: entry[:segment_id])
          before = tier.attributes.slice(*tracked)
          tier.position = entry[:catch_all] || !entry[:active] ? tier.position.to_i : (position += 1)
          before_caps = Agreements::Caps.normalize(tier.agreement_caps)
          tier.assign_attributes(entry.slice(:active, *Tier::RULE_FIELDS))
          # R209: variáveis de acordo mudadas puxam os limites dos perfis (com o item ainda sujo, antes de gravar).
          Agreements::Settings.new(@user).follow_limits(tier, before_caps) if tier.persisted? && (tier.changed & (Tier::AGREEMENT_VARIABLE_FIELDS + [ :agreement_caps ]).map(&:to_s)).any?
          tier.save!
          if tier.previously_new_record?
            copy_limits(tier, entry[:copy_from])
            log("tier", tier.id, "created", "segment", nil, tier.name, tenant)
          else
            tier.attributes.slice(*tracked).each do |field, after|
              next if before[field] == after

              log("tier", tier.id, field == "active" ? (after ? "reactivated" : "removed") : "updated", field, before[field].to_s, after.to_s, tenant)
            end
          end
        end
      end

      # SG15: o item novo copia as alçadas da promessa e os limites de acordo por perfil do item de origem.
      def copy_limits(tier, source_id)
        return unless source_id.to_i.positive?

        PromiseLimit.where(tier_id: source_id).find_each { |limit| PromiseLimit.where(tier_id: tier.id, profile_id: limit.profile_id).update_all(max_days: limit.max_days) }
        AgreementLimit.where(tier_id: source_id).find_each do |limit|
          AgreementLimit.where(tier_id: tier.id, profile_id: limit.profile_id).update_all(limit.attributes.except("id", "tier_id", "profile_id", "created_at", "updated_at"))
        end
      end

      # Parâmetros e políticas de encargos do credor (09, R160, R163, R180 a R182): registra cada campo que mudou, com antes e depois.
      def save_charges(tenant, setting, proposal)
        setting.assign_attributes(proposal.charges.slice(*TenantSetting::CHARGE_FIELDS))
        setting.changes.slice(*TenantSetting::CHARGE_FIELDS).each do |field, (before, after)|
          log("tenant_setting", setting.id, "updated", field, before.to_s, after.to_s, tenant)
        end
      end

      def tracked = %w[position active] + Tier::RULE_FIELDS.map(&:to_s)

      def log(type, id, event, field, before, after, tenant)
        Change.record!(tenant_id: tenant.id, user: @user, subject_type: type, subject_id: id, event: event, field: field, before: before, after: after, origin: "screen")
      end
  end
end
