# Origem nas listas da equipe do credor (14, R318): coluna e filtro "Origem" (equipe do credor ou uma operação) nas listas de acionamentos,
# promessas e acordos, só quando algum credor do usuário tem operação credenciada. Para o usuário de operação, a coluna não aparece.
module OriginFilter
  extend ActiveSupport::Concern

  included { helper_method :origin_label }

  private
    def load_origins(tenant_ids)
      @origins = Operations::Context.operation? ? [] : Operation.joins(:accreditations).where(accreditations: { tenant_id: tenant_ids }).distinct.order(:short_name).pluck(:short_name, :id)
    end

    def apply_origin(scope)
      case params[:origin].to_s
      when "" then scope
      when "team" then scope.where(operation_id: nil)
      else scope.where(operation_id: params[:origin].to_i)
      end
    end

    def origin_label(record) = record.operation&.short_name || "Equipe do credor"
end
