# Réguas (21, R428 a R445): a lista do credor, por prioridade; o diagrama de raias (revisão 1 das telas), com as densidades confortável e compacta e
# o modo de análise; criar, editar, ligar, desligar, mudar a prioridade, e a conferência do impacto. Permissão 24.
class CadencesController < ApplicationController
  include CadenceAccess

  before_action :set_cadence, only: %i[show edit update enable disable priority review confirm]

  def index
    authorize Cadence
    @tenants = manageable_tenants
    @tenant = @tenants.find_by(id: params[:credor]) || @tenants.first
    @cadences = @tenant ? Cadence.where(tenant: @tenant).by_priority.includes(:lanes, :columns).to_a : []
    @last_rounds = CadenceRound.where(cadence_id: @cadences.map(&:id)).where.not(state: "scheduled").order(:scheduled_for)
                               .group_by(&:cadence_id).transform_values(&:last)
    @commands = CadenceCommand.where(cadence_round_id: @last_rounds.values.map(&:id)).group(:cadence_round_id).count
    @cable = cable if @tenant
  end

  def show
    @density = params[:densidade] == "compacta" ? "compacta" : "confortavel"
    @analysis = params[:modo] == "analise"
    @diagram = Cadences::Diagram.new(@cadence, analysis: @analysis)
    @cable = cable
  end

  def new
    authorize Cadence
    @tenants = manageable_tenants
    @cadence = Cadence.new(tenant_id: params[:credor].presence || @tenants.first&.id, schedule_days: [ 1, 2, 3, 4, 5 ], schedule_time: "09:30",
                           valid_from: Date.current, milestone: "contract_arrears")
  end

  def create
    @tenants = manageable_tenants
    attributes = cadence_params(:tenant_id, :milestone)
    tenant = @tenants.find_by(id: attributes[:tenant_id]) or return head(:not_found)
    authorize Cadence.new(tenant: tenant)
    @cadence = Cadence.new(attributes.merge(tenant: tenant))
    @cadence.save!
    Change.record!(@cadence, "created", tenant_id: tenant.id, actor: Current.user, field: "name", after: @cadence.name)
    panel_finish(cadence_path(@cadence), notice: t(".done", name: @cadence.name), navegar: true)
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
  end

  def update
    change([ { "op" => "update" }.merge(cadence_params.to_h) ], notice: t(".done"))
  end

  def enable = change([ { "op" => "enable" } ], notice: t(".done"))
  def disable = change([ { "op" => "disable" } ], notice: t(".done"))
  def priority = change([ { "op" => "move_priority", "to" => params[:para].to_i } ], notice: t(".done"))

  def review
    @token = params[:token].to_s
    @proposal = Cadences::Proposal.from_token(@cadence, @token)
    @result = Cadences::Review.read(@token)
    @failure = ImpactReview.failure(Cadences::Review, @token)
    @cable = cable
    render partial: "cadences/review", locals: { result: @result, failure: @failure } if fragment?
  rescue Cadences::Refused => error
    redirect_to cadence_path(@cadence), alert: error.message, status: :see_other
  end

  def confirm
    Cadences::Applier.new(Current.user).confirm(@cadence, params[:token].to_s)
    panel_finish(cadence_path(@cadence), notice: t(".done"), navegar: true, mesma_aba: true)
  rescue Cadences::Refused => error
    panel_finish(cadence_path(@cadence), notice: error.message, tom: :danger, navegar: true, mesma_aba: true)
  end

  private
    # Os dias da agenda chegam como lista de "0" a "6"; o prazo de retorno, por tipo, em horas.
    def cadence_params(*extra)
      fields = [ *extra, :name, :schedule_time, :skip_national_holidays, :valid_from, :valid_until, { schedule_days: [] }, { return_hours: Cadences::Catalog::KINDS } ]
      attributes = params.expect(cadence: fields)
      attributes[:schedule_days] = Array(attributes[:schedule_days]).compact_blank.map(&:to_i) if attributes.key?(:schedule_days)
      attributes[:skip_national_holidays] = attributes[:skip_national_holidays] == "1" if attributes.key?(:skip_national_holidays)
      if attributes.key?(:return_hours)
        attributes[:return_hours] = attributes[:return_hours].to_h.compact_blank.transform_values(&:to_i)
          .reject { |kind, hours| hours == Cadences::Catalog::RETURN_HOURS[kind] }
      end
      attributes
    end
end
