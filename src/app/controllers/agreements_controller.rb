# Lista de acordos (11, R243) e a página de um acordo (proposta, termo e aceite). A lista mistura os credores em que o usuário tem "negociar acordos" (16),
# com a coluna Credor quando são mais de um e um filtro opcional, sem estado guardado (MT-4 a MT-6, R245a). Abrir pelo endereço um acordo de credor sem a
# permissão responde "não encontrado" e fica registrado (R33). A lista se refaz por evento do WebSocket, sem polling.
class AgreementsController < ApplicationController
  def index
    authorize Agreement
    scope = policy_scope(Agreement).includes(:customer, :tenant, :user, :decided_by)
    @tenants = Tenant.where(id: scope.reorder(nil).distinct.pluck(:tenant_id)).order(:name).pluck(:name, :id)
    @several_tenants = @tenants.size > 1
    @filters = filters
    scope = scope.where(tenant_id: @filters[:tenant]) if @filters[:tenant].present?
    scope = scope.where(state: @filters[:state]) if Agreement::STATES.include?(@filters[:state])
    scope = scope.where(user_id: @filters[:user]) if @filters[:user].present?
    scope = scope.where(built_on: @filters[:from]..) if @filters[:from]
    scope = scope.where(built_on: ..@filters[:to]) if @filters[:to]
    @operators = User.where(id: policy_scope(Agreement).select(:user_id)).order(:name).pluck(:name, :id)
    @pagination = Pagination.new(scope.recent, page: params[:page], per_page: params[:per_page])
    @agreements = @pagination.records.to_a
    @cases = Agreements::ManagerCases.for(Current.user) if params[:page].blank?
    @cable = Current.user.tenant_ids_with("negotiate_agreements").map { |id| { channel: "AgreementsChannel", tenant_id: id } }.to_json
    render partial: "agreements/result" if htmx_fragment?
  end

  def show
    @agreement = Agreement.includes(:tenant, :customer, :segment, :user, :decided_by, :registered_by, agreement_bills: %i[bill contract]).find(params[:id])
    authorize @agreement
    @term = @agreement.term_snapshot.presence || Agreements::Term.build(@agreement)
    @events = @agreement.events.includes(:user).order(:occurred_at, :id)
    @acceptors = Agreements::Acceptance.acceptors(@agreement) if @agreement.state_approved?
    # Depois do aceite (11, R221 a R236): os títulos de acordo com o devido hoje, e os cálculos de quitação vigentes (R230).
    @titles = @agreement.titles.to_a
    @reversal_titles = @agreement.reversal_titles.to_a
    @ledgers = Agreements::LedgerLoader.new(@agreement.tenant).call((@titles + @reversal_titles).select { |bill| bill.status_in_collection? })
    @settlements = @agreement.settlements.where(expired_at: nil).where(on_date: Date.current..).order(:on_date)
    @cable = [ { channel: "AgreementsChannel", customer_id: @agreement.customer_id } ].to_json
  end

  private
    def filters
      { tenant: params[:tenant].presence, state: params[:state].presence, user: params[:user].presence, from: parse_date(params[:from]), to: parse_date(params[:to]) }
    end

    def parse_date(text)
      Date.iso8601(text.to_s)
    rescue Date::Error
      nil
    end
end
