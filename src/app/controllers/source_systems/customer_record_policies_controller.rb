module SourceSystems
  # Política "Cadastro entre sistemas" do credor (17, R410): quem prevalece no nome e nos dados do cliente quando mais de um sistema o informa.
  # É da permissão 23, no credor; vale para as cargas seguintes.
  class CustomerRecordPoliciesController < ApplicationController
    def update
      tenant = Tenant.find(params[:credor])
      authorize SourceSystem.new(tenant: tenant), :update?
      Manager.new(Current.user).update_customer_record_policy(tenant, policy: params[:customer_record_policy], system_id: params[:customer_record_system_id])
      panel_finish(source_systems_path, notice: t(".done", tenant: tenant.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid => error
      panel_refuse(source_systems_path, "#{error.record.errors.full_messages.to_sentence.upcase_first}.")
    end
  end
end
