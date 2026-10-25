module Indexes
  # Os meses das quatro séries para a tela de índices (R147): 24 por página, do mais novo para o mais antigo. Cada célula traz o valor
  # global do Banco Central (e se é parcial) e a correção do credor, se houver (R145, R146). Consulta: `index_rates (series, month)` e
  # `index_adjustments (tenant_id, series, month)`; tabelas pequenas.
  class Grid
    PER_PAGE = 24
    Cell = Data.define(:bank, :partial, :fetched_at, :adjustment)

    attr_reader :page

    def initialize(tenant_ids, page:)
      @tenant_ids = tenant_ids
      @page = [ page.to_i, 1 ].max
      @all_months = (IndexRate.distinct.pluck(:month) + IndexAdjustment.where(tenant_id: tenant_ids).distinct.pluck(:month)).uniq.sort.reverse
    end

    def pages = [ (@all_months.size / PER_PAGE.to_f).ceil, 1 ].max
    def months = @months ||= @all_months.slice((page - 1) * PER_PAGE, PER_PAGE) || []
    def empty? = @all_months.empty?

    def rates = @rates ||= IndexRate.where(month: months).index_by { |rate| [ rate.series, rate.month ] }

    def adjustments(tenant_id)
      @adjustments ||= IndexAdjustment.where(tenant_id: @tenant_ids, month: months).includes(:user).group_by(&:tenant_id).transform_values { |list| list.index_by { |adj| [ adj.series, adj.month ] } }
      @adjustments.fetch(tenant_id, {})
    end

    def cell(tenant_id, series, month)
      rate = rates[[ series, month ]]
      Cell.new(rate&.value, rate&.partial, rate&.fetched_at, adjustments(tenant_id)[[ series, month ]])
    end
  end
end
