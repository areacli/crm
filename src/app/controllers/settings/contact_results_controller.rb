module Settings
  # Resultados de acionamento do credor (R66, R67), uma aba da configuração (P21): lista na ordem do credor, cadastro, edição de nome e regra de
  # retorno, desativar e reativar, subir e descer. A permissão 9 vale no credor do resultado; quem a tem em mais de um credor vê os de todos.
  class ContactResultsController < ApplicationController
    before_action :set_result, only: %i[edit update]

    def index
      authorize ContactResult
      @tenants = manageable_tenants.to_a
      @several_tenants = @tenants.size > 1
      @results = policy_scope(ContactResult).includes(:tenant).ordered.group_by(&:tenant)
      @used = ContactAttempt.where(result_id: @results.values.flatten.map(&:id)).group(:result_id).count
    end

    def new
      authorize ContactResult
      @tenants = manageable_tenants.to_a
      @result = ContactResult.new(kind: :spoke_with_customer, return_rule: :allowed)
    end

    def create
      @tenants = manageable_tenants.to_a
      attributes = params.expect(contact_result: %i[tenant_id name kind return_rule invalidates_contact])
      tenant = @tenants.find { |candidate| candidate.id.to_s == attributes[:tenant_id].to_s } or return head(:not_found)
      authorize ContactResult.new(tenant: tenant)
      @result = manager.create(tenant: tenant, name: attributes[:name], kind: attributes[:kind], return_rule: attributes[:return_rule],
                              invalidates_contact: attributes[:invalidates_contact] == "1")
      redirect_to settings_contact_results_path, notice: t(".done", name: @result.name), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @result = error.record
      render :new, status: :unprocessable_content
    end

    def edit
    end

    def update
      attributes = params.expect(contact_result: %i[name return_rule invalidates_contact])
      manager.update(@result, name: attributes[:name], return_rule: attributes[:return_rule], invalidates_contact: attributes[:invalidates_contact] == "1")
      redirect_to settings_contact_results_path, notice: t(".done", name: @result.name), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @result = error.record
      render :edit, status: :unprocessable_content
    end

    private
      def set_result
        @result = ContactResult.includes(:tenant).find(params[:id])
        authorize @result
      end

      def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_contact_results")).order(:name)

      def manager = Contacts::ResultManager.new(Current.user)
  end
end
