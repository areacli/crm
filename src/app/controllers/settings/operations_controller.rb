# Operações credenciadas (14, R306, R307, R325): lista, credenciar pelo CNPJ e a ficha do credenciamento, com as pessoas da operação e os
# vínculos delas neste credor. A permissão 18 vale no credor do credenciamento.
module Settings
  class OperationsController < ApplicationController
    def index
      authorize Accreditation
      @tenants = manageable_tenants
      @several_tenants = @tenants.size > 1
      scope = policy_scope(Accreditation).includes(:tenant, :operation).joins(:operation).order("operations.short_name")
      scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
      @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
      @accreditations = @pagination.records
      @linked = Membership.active.where.not(operation_id: nil).where(tenant_id: @accreditations.map(&:tenant_id))
                          .group(:tenant_id, :operation_id).count
    end

    def new
      authorize Accreditation
      @tenants = manageable_tenants
    end

    def create
      @tenants = manageable_tenants
      attributes = params.expect(operation: %i[tenant_id cnpj legal_name short_name manager_name manager_email])
      tenant = @tenants.find_by(id: attributes[:tenant_id]) or return head(:not_found)
      authorize Accreditation.new(tenant: tenant)
      accreditation, user, password = ::Operations::Accreditor.new(Current.user).accredit(
        tenant: tenant, cnpj: attributes[:cnpj], legal_name: attributes[:legal_name], short_name: attributes[:short_name],
        manager_name: attributes[:manager_name], manager_email: attributes[:manager_email]
      )
      flash[:temporary_password] = { "email" => user.email_address, "password" => password } if password
      panel_finish(settings_operation_path(accreditation), notice: t(".done", name: accreditation.operation.short_name, tenant: tenant.name), navegar: true)
    rescue ActiveRecord::RecordInvalid => error
      refuse(error.record.errors.full_messages.to_sentence)
    rescue ::Operations::Accreditor::Refused => error
      refuse(error.message)
    end

    def show
      @accreditation = policy_scope(Accreditation).includes(:tenant, :operation).find(params[:id])
      authorize @accreditation
      @operation = @accreditation.operation
      @members = @operation.members.includes(:user).order(:manager).reverse_order
      @memberships = Membership.where(tenant_id: @accreditation.tenant_id, operation_id: @operation.id).includes(:profile).index_by(&:user_id)
    end

    private
      def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_operations")).order(:name)

      def refuse(message)
        @error = message
        render :new, status: :unprocessable_content
      end
  end
end
