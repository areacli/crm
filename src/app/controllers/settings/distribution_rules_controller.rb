# Enquadramento da distribuição (14, R342 a R347): os itens em ordem, com o segmento, as operações e a exposição; incluir, mudar, mover e tirar
# montam uma proposta, que passa pela conferência do impacto em segundo plano antes de valer. Permissão 19, no credor escolhido.
module Settings
  class DistributionRulesController < ApplicationController
    before_action :set_tenant

    def index
      @items = DistributionRuleItem.where(tenant: @tenant).ordered.includes(:segment).to_a
      @counts = Distribution.in_force.where(tenant: @tenant, source: "rule").group(:rule_item_id).count
      @operations = Operation.where(id: @items.flat_map(&:operation_ids)).pluck(:id, :short_name).to_h
      @cable = [ { channel: "DistributionsChannel", tenant_id: @tenant.id } ].to_json
    end

    def new
      load_choices
    end

    def create
      attributes = params.expect(rule: [ :segment_id, :exposure, :position, operation_ids: [] ])
      proposal = DistributionRules::Proposal.current(@tenant).with_included(attributes[:segment_id], Array(attributes[:operation_ids]).compact_blank, attributes[:exposure], attributes[:position].to_i)
      review(proposal)
    rescue Distributions::Refused => error
      load_choices
      @error = error.message
      render :new, status: :unprocessable_content
    end

    def edit
      @index = params[:id].to_i
      @item = DistributionRules::Proposal.current(@tenant).items.fetch(@index)
      @segment = Segment.find(@item.segment_id)
      load_choices
    end

    def update
      attributes = params.expect(rule: [ :exposure, operation_ids: [] ])
      review(DistributionRules::Proposal.current(@tenant).with_changed(params[:id].to_i, Array(attributes[:operation_ids]).compact_blank, attributes[:exposure]))
    rescue Distributions::Refused, IndexError => error
      panel_finish(settings_distribution_rules_path(credor: @tenant.id), notice: error.message, tom: :danger, navegar: true, mesma_aba: true)
    end

    def move = review(DistributionRules::Proposal.current(@tenant).with_moved(params[:id].to_i, params[:deslocamento].to_i))
    def destroy = review(DistributionRules::Proposal.current(@tenant).with_removed(params[:id].to_i))

    def review_show
      @token = params[:token].to_s
      @proposal = DistributionRules::Proposal.from_token(@tenant, @token)
      @result = DistributionRules::Review.read(@token)
      @segments = Segment.where(id: @proposal.items.map(&:segment_id)).pluck(:id, :name).to_h
      @operations = Operation.where(id: @proposal.items.flat_map(&:operation_ids)).pluck(:id, :short_name).to_h
      @cable = [ { channel: "DistributionsChannel", tenant_id: @tenant.id } ].to_json
      render partial: "settings/distribution_rules/review", locals: { result: @result } if fragment?
    rescue Distributions::Refused => error
      redirect_to settings_distribution_rules_path(credor: @tenant.id), alert: error.message, status: :see_other
    end

    def confirm
      DistributionRules::Applier.new(Current.user).confirm(@tenant, params[:token].to_s)
      panel_finish(settings_distribution_rules_path(credor: @tenant.id), notice: t(".done"), navegar: true, mesma_aba: true)
    rescue Distributions::Refused => error
      panel_finish(settings_distribution_rules_path(credor: @tenant.id), notice: error.message, tom: :danger, navegar: true, mesma_aba: true)
    end

    private
      def set_tenant
        tenants = Tenant.where(id: Current.user.tenant_ids_with("distribute_portfolio")).order(:name)
        @tenant = tenants.find_by(id: params[:credor]) || tenants.first or raise Pundit::NotAuthorizedError
        @tenants = tenants
        authorize Distribution.new(tenant: @tenant), :create?
      end

      def load_choices
        used = DistributionRuleItem.where(tenant: @tenant).active.pluck(:segment_id)
        @segments = Segment.where(tenant: @tenant, subject: "contracts", active: true).where.not(id: used).order(:name_key)
        @accredited = Operation.joins(:accreditations).merge(Accreditation.active.where(tenant: @tenant)).order(:short_name)
        @current = DistributionRuleItem.where(tenant: @tenant).ordered.includes(:segment).to_a
      end

      def review(proposal)
        token = proposal.token
        DistributionRulesJob.perform_later(@tenant, token: token)
        url = review_settings_distribution_rules_path(credor: @tenant.id, token: token)
        # Na SPA, a conferência toma o lugar do enquadramento na mesma aba; o "Confirmar" e o "Descartar" voltam a ele.
        panel_finish(url, navegar: true, mesma_aba: true)
      end
  end
end
