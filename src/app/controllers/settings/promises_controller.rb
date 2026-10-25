module Settings
  # Aba "Promessas" da configuração (10, R189, R190, R206, T6): as políticas do credor, o prazo máximo de cada segmento e a alçada de cada perfil, com as
  # alterações recentes. Um bloco por credor em que a pessoa tem a permissão 14 (A7); mudar as de um credor não muda as de outro.
  class PromisesController < ApplicationController
    def show
      authorize TenantSetting, :show?, policy_class: PromiseSettingPolicy
      load_tenants
    end

    private
      def load_tenants
        @tenants = Tenant.where(id: Current.user.tenant_ids_with("change_financial_policies")).includes(:setting).order(:name).to_a
        @segments = Segment.where(tenant_id: @tenants.map(&:id)).ordered.group_by(&:tenant_id)
        @profiles = Profile.where(tenant_id: @tenants.map(&:id)).order(:name).group_by(&:tenant_id)
        @limits = PromiseLimit.where(segment_id: @segments.values.flatten.map(&:id)).group_by(&:segment_id).transform_values { |rows| rows.index_by(&:profile_id) }
        @history = Change.where(tenant_id: @tenants.map(&:id), subject_type: %w[promise_settings promise_limit agreement_settings agreement_segment agreement_limit]).includes(:user)
                         .order(occurred_at: :desc, id: :desc).limit(60).group_by(&:tenant_id)
        @agreement_history = @history.transform_values { |changes| changes.select { |change| change.subject_type == "agreement_settings" } }
        @segment_names = @segments.values.flatten.index_by(&:id)
        @profile_names = @profiles.values.flatten.index_by(&:id)
      end
  end
end
