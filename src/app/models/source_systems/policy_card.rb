module SourceSystems
  # O cartão da política "Cadastro entre sistemas" de um credor (17, R410): só existe para o credor com mais de um sistema além do CRM, que é
  # quando dois sistemas podem informar o mesmo cliente. Leva a escolha atual, os sistemas que podem prevalecer e a última alteração (PD4).
  PolicyCard = Data.define(:tenant, :setting, :systems, :last_change) do
    # @param scope [ActiveRecord::Relation] os sistemas que o usuário alcança
    def self.for(scope)
      receiving = scope.receiving.includes(:tenant).order(Arel.sql("lower(source_systems.name)")).group_by(&:tenant).select { |_tenant, systems| systems.size > 1 }
      return [] if receiving.empty?

      settings = TenantSetting.where(tenant_id: receiving.keys.map(&:id)).includes(:customer_record_system).index_by(&:tenant_id)
      changes = Change.where(subject_type: "settings", subject_id: receiving.keys.map(&:id), field: "customer_record_policy").includes(:user)
                      .order(occurred_at: :desc, id: :desc).group_by(&:subject_id)
      receiving.sort_by { |tenant, _systems| tenant.name }.map do |tenant, systems|
        new(tenant: tenant, setting: settings.fetch(tenant.id), systems: systems, last_change: changes[tenant.id]&.first)
      end
    end
  end
end
