module Promises
  # Políticas do credor, prazo máximo do segmento e alçada por perfil (10, R189, R190, R206; permissão 14). Cada mudança fica registrada com quem,
  # quando, antes e depois (PD4) e vale só para as promessas novas (R187).
  class Settings
    def initialize(actor) = @actor = actor

    # `values`: os campos de TenantSetting::PROMISE_POLICIES como a tela envia.
    def update_policies(tenant, values)
      setting = tenant.setting
      values = values.to_h.stringify_keys.slice(*TenantSetting::PROMISE_POLICIES)
      setting.assign_attributes(values.transform_values { |value| value.is_a?(String) && value.strip.empty? ? nil : value })
      ApplicationRecord.transaction do
        setting.changes.each do |field, (before, after)|
          Change.record!(tenant: tenant, user: @actor, subject_type: "promise_settings", subject_id: tenant.id, event: "#{field}_changed", field: field, before: before.to_s, after: after.to_s)
        end
        setting.save!
      end
      setting
    end

    # `segments`: { id do segmento => { max_days:, limits: { id do perfil => dias } } } do credor. O prazo do segmento baixa as alçadas que passavam dele, com
    # registro; a alçada nunca passa do prazo do segmento (R190).
    def update_limits(tenant, segments)
      ApplicationRecord.transaction do
        Segment.where(tenant_id: tenant.id, id: segments.keys).find_each do |segment|
          values = segments.fetch(segment.id)
          days = Integer(values[:max_days].to_s, exception: false)
          raise Refused, I18n.t("promises.settings.invalid_days", segment: segment.name) unless days&.between?(1, 365)

          lower_limits(segment, days) if days < segment.promise_max_days
          log_days(segment, segment.promise_max_days, days)
          segment.update!(promise_max_days: days)
          values.fetch(:limits, {}).each { |profile_id, raw| set_limit(segment, profile_id.to_s.to_i, raw, days) }
        end
      end
    end

    private
      def lower_limits(segment, days)
        PromiseLimit.where(segment_id: segment.id).where("max_days > ?", days).includes(:profile).find_each do |limit|
          log_limit(segment, limit.profile_id, limit.max_days, days, event: "lowered")
          limit.update!(max_days: days)
        end
      end

      def set_limit(segment, profile_id, raw, ceiling)
        limit = PromiseLimit.find_by(segment_id: segment.id, profile_id: profile_id) or return
        days = Integer(raw.to_s, exception: false)
        raise Refused, I18n.t("promises.settings.invalid_limit", segment: segment.name) unless days&.between?(0, ceiling)

        return if days == limit.max_days

        log_limit(segment, profile_id, limit.max_days, days, event: "changed")
        limit.update!(max_days: days)
      end

      def log_days(segment, before, after)
        return if before == after

        Change.record!(tenant_id: segment.tenant_id, user: @actor, subject_type: "promise_limit", subject_id: segment.id, event: "max_days_changed", field: "max_days", before: before.to_s, after: after.to_s)
      end

      def log_limit(segment, profile_id, before, after, event:)
        Change.record!(tenant_id: segment.tenant_id, user: @actor, subject_type: "promise_limit", subject_id: segment.id, event: "limit_#{event}", field: "profile:#{profile_id}", before: before.to_s, after: after.to_s)
      end
  end
end
