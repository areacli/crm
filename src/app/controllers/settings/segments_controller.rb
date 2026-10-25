module Settings
  # Segmentos do contrato (08, R148 a R158), uma aba da configuração: lista por credor, criar e editar. Criar e editar levam à conferência do
  # impacto antes de valer (R154). Quem tem só a 4 vê tudo sem os botões (R157).
  class SegmentsController < ApplicationController
    include SegmentReview

    before_action :set_segment, only: %i[edit update]

    def index
      authorize Segment
      load_index
    end

    def new
      @tenant = tenant_for_change(params[:tenant_id])
      @segment = Segment.new(tenant: @tenant)
      @raw = {}
    end

    def create
      @tenant = tenant_for_change(params[:tenant_id])
      @segment = Segment.new(tenant: @tenant)
      build(@segment) ? render_review(::Segments::Proposal.current(@tenant).with_created(@segment)) : render(:new, status: :unprocessable_content)
    end

    def edit
      @raw = {}
    end

    def update
      @tenant = @segment.tenant
      build(@segment) ? render_review(::Segments::Proposal.current(@tenant).with_updated(@segment)) : render(:edit, status: :unprocessable_content)
    end

    private
      def set_segment
        @segment = Segment.includes(:tenant).find(params[:id])
        authorize @segment
        @tenant = @segment.tenant
      end

      # Atribui, valida e junta os erros de número; devolve true se está tudo certo. O segmento não é gravado.
      def build(segment)
        @raw = params.expect(segment: ::Segments::Params::FIELDS + [ :tenant_id ]).to_h.symbolize_keys
        attributes, invalid = ::Segments::Params.parse(@raw)
        segment.assign_attributes(attributes)
        segment.valid?
        invalid.each { |column, key| segment.errors.add(column, t("segments.errors.#{key}")) }
        segment.errors.empty?
      end

      def load_index
        @tenant_ids = policy_scope(Segment).distinct.pluck(:tenant_id)
        @tenants = Tenant.where(id: @tenant_ids).order(:name).to_a
        @segments = policy_scope(Segment).ordered.group_by(&:tenant_id)
        @settings = TenantSetting.where(tenant_id: @tenant_ids).index_by(&:tenant_id)
        @totals = ::Segments::Totals.new(@tenants).call
        @runs = @tenants.to_h { |tenant| [ tenant.id, TaskRun.where(tenant_id: tenant.id, name: ::Segments::Recalculation::NAME).recent.first ] }
        @can_change = Current.user.tenant_ids_with("change_financial_policies")
      end
  end
end
