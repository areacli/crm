# Políticas das operações (14, R319), do credor, valendo para todas as operações credenciadas nele: exclusividade, exposição padrão, dias úteis
# antes de uma fatura vencida estar pra operação, visibilidade do que é de outra origem e vínculos dados pelo gestor da operação. Permissão 18.
module Settings
  class OperationPoliciesController < ApplicationController
    FIELDS = %i[operation_exclusive operation_default_exposure operation_exposure_business_days operation_sees_other_deals operation_other_contact_attempts operation_manager_links].freeze

    def update
      tenant = Tenant.find_by(id: params[:credor]) or return head(:not_found)
      authorize Accreditation.new(tenant: tenant), :update?
      setting = tenant.setting
      attributes = params.expect(policies: FIELDS)
      before = setting.slice(*FIELDS)
      ApplicationRecord.transaction do
        setting.update!(attributes)
        setting.slice(*FIELDS).each do |field, after|
          next if before[field] == after

          Change.record!(setting, "updated", tenant_id: tenant.id, actor: Current.user, origin: "screen", field: field, before: before[field].to_s, after: after.to_s)
        end
      end
      ::Operations::ReachBuilder.new(tenant).rebuild if before["operation_exposure_business_days"] != setting.operation_exposure_business_days
      panel_finish(settings_operations_path, notice: t(".done", tenant: tenant.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid => error
      panel_finish(settings_operations_path, notice: error.record.errors.full_messages.to_sentence, tom: :danger)
    end
  end
end
