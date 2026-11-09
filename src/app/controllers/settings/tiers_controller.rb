module Settings
  # Enquadramento financeiro (13, R265 a R272, R292 a R294): os itens em ordem, com as regras de cada um. Incluir, tirar e editar as regras
  # levam à conferência do impacto antes de valer. Quem tem só a 4 vê tudo sem os botões (R276).
  class TiersController < ApplicationController
    include TierReview

    before_action :set_tier, only: %i[edit update destroy]

    def index
      authorize Tier
      @tenant_ids = policy_scope(Tier).distinct.pluck(:tenant_id)
      @tenants = Tenant.where(id: @tenant_ids).order(:name).to_a
      @tiers = policy_scope(Tier).financial.includes(:segment).ordered.group_by(&:tenant_id)
      @settings = TenantSetting.where(tenant_id: @tenant_ids).index_by(&:tenant_id)
      @totals = ::Tiers::Totals.new(@tenants).call
      @runs = @tenants.to_h { |tenant| [ tenant.id, TaskRun.where(tenant_id: tenant.id, name: ::Tiers::Recalculation::NAME).recent.first ] }
      @value_status = @tenants.to_h { |tenant| [ tenant.id, Charges::Recalculation.status(tenant) ] }
      @can_change = Current.user.tenant_ids_with("change_financial_policies")
    end

    # Incluir segmento (R293): modal pequeno com o segmento e a posição; as regras vêm de um item escolhido (SG15).
    def new
      @tenant = tenant_for_change(params[:credor])
      load_inclusion
    end

    def create
      @tenant = tenant_for_change(params[:credor])
      raw = params.expect(tier: %i[segment_id before_id copy_from_id])
      segment = Segment.active_ones.find_by(id: raw[:segment_id], tenant_id: @tenant.id, subject: "contracts")
      unless segment && !Tier.financial.where(tenant_id: @tenant.id, segment_id: segment.id, active: true).exists?
        load_inclusion
        @error = t("activerecord.errors.models.tier.attributes.segment.required")
        return render(:new, status: :unprocessable_content)
      end

      proposal = ::Tiers::Proposal.current(@tenant).with_included(segment, before_id: raw[:before_id].to_i, copy_from_id: raw[:copy_from_id].to_i)
      render_review(proposal)
    end

    # Editar regras (R294): encargos, promessa e acordo do item, cada campo dizendo se é do credor ou próprio.
    def edit
      @raw = {}
    end

    def update
      @raw = params.expect(tier: ::Tiers::RuleParams::CHARGE_FIELDS).to_h.symbolize_keys
      attributes, invalid = ::Tiers::RuleParams.parse(@raw)
      @tier.assign_attributes(attributes)
      @tier.valid?
      invalid.each { |column, key| @tier.errors.add(column, t("tiers.errors.#{key}")) }
      return render(:edit, status: :unprocessable_content) if @tier.errors.any?

      render_review(::Tiers::Proposal.current(@tenant).with_rules(@tier.id, attributes), back: edit_settings_tier_path(@tier))
    end

    # Tirar do enquadramento (R266): conferência antes de valer.
    def destroy
      authorize @tier, :destroy?
      render_review(::Tiers::Proposal.current(@tenant).with_removed(@tier.id))
    end

    private
      def set_tier
        @tier = Tier.includes(:segment, :tenant).find(params[:id])
        authorize @tier
        @tenant = @tier.tenant
      end

      def load_inclusion
        used = Tier.financial.where(tenant_id: @tenant.id, active: true).where.not(segment_id: nil).pluck(:segment_id)
        @candidates = Segment.active_ones.where(tenant_id: @tenant.id, subject: "contracts").where.not(id: used).ordered.to_a
        @customer_segments = Segment.active_ones.where(tenant_id: @tenant.id, subject: "customers").count
        @items = Tier.financial.where(tenant_id: @tenant.id, active: true).includes(:segment).ordered.to_a
      end
  end
end
