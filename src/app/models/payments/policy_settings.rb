module Payments
  # Políticas de pagamento do credor (R46, R46a, R62a, R64; permissão 14): cada mudança fica registrada (quem, quando, antes e depois, PD4).
  class PolicySettings
    def initialize(actor) = @actor = actor

    def update(tenant, values)
      setting = tenant.setting
      setting.assign_attributes(values.slice(*TenantSetting::PAYMENT_POLICIES))
      ApplicationRecord.transaction do
        setting.changes.each do |field, (before, after)|
          Change.create!(tenant: tenant, user: @actor, subject_type: "settings", subject_id: tenant.id, event: "#{field}_changed", field: field, before: before, after: after)
        end
        setting.save!
      end
      setting
    end
  end
end
