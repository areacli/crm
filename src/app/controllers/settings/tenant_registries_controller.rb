# Dados do credor (06, R106), uma aba da configuração: CNPJ, razão social, nome fantasia, endereço, e-mail e telefone. A permissão 4 vale no
# credor editado; quem a tem em mais de um vê o cadastro de cada um, separadamente, sem seleção de credor (R106a).
module Settings
  class TenantRegistriesController < ApplicationController
    def show
      authorize TenantSetting, :show?, policy_class: TenantSettingPolicy
      load_tenants
    end

    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: TenantSettingPolicy
      Registry::TenantEditor.new(Current.user).update(tenant, params.expect(tenant: Tenant::REGISTRY_FIELDS).to_h)
      redirect_to settings_tenant_registry_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue ActiveRecord::RecordInvalid
      load_tenants
      @invalid = tenant
      render :show, status: :unprocessable_content
    end

    private
      def load_tenants
        @tenants = Tenant.where(id: Current.user.tenant_ids_with("change_settings")).order(:name).to_a
        # Última mudança do cadastro de cada credor (R106): quem e quando.
        @last_change = Change.where(subject_type: "tenant", subject_id: @tenants.map(&:id), event: "registry_changed").includes(:user)
                             .order(occurred_at: :desc, id: :desc).group_by(&:subject_id).transform_values(&:first)
      end
  end
end
