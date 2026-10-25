# Lista de acionamentos dos credores em que o usuário consulta a carteira (R78): período (padrão, os últimos 7 dias; até 92 por consulta),
# operador, canal, resultado, tipo e credor. Mistura os credores, com a coluna Credor quando são mais de um (MT-4 a MT-6);
# a busca e a paginação refazem só o trecho, e um acionamento novo de qualquer operador refaz a página atual pelo WebSocket.
class ContactAttemptsController < ApplicationController
  MAX_PERIOD_DAYS = 92
  DEFAULT_PERIOD_DAYS = 7

  def index
    authorize ContactAttempt
    @tenant_ids = Current.user.tenant_ids_with("view_portfolio")
    @several_tenants = @tenant_ids.size > 1
    @period = period
    scope = policy_scope(ContactAttempt).where(contacted_at: @period)
    scope = scope.where(user_id: params[:operator]) if params[:operator].present?
    scope = scope.where(channel: params[:channel]) if ContactAttempt::CHANNELS.include?(params[:channel])
    scope = scope.where(result_id: params[:result]) if params[:result].present?
    scope = scope.where(result_kind: params[:kind]) if ContactResult::KINDS.key?(params[:kind].to_s.to_sym)
    scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
    @pagination = Pagination.new(scope.includes(:customer, :contract, :result, :user, :tenant).recent, page: params[:page], per_page: params[:per_page])
    @attempts = @pagination.records
    load_filter_options
    render partial: "contact_attempts/result" if htmx_fragment?
  end

  private
    # O período vem de duas datas; sem elas, os últimos 7 dias, e nunca mais de 92 dias por consulta (R78).
    def period
      to = parse_date(params[:to]) || Date.current
      from = parse_date(params[:from]) || to - DEFAULT_PERIOD_DAYS.days
      from = to - MAX_PERIOD_DAYS.days if (to - from) > MAX_PERIOD_DAYS
      @from, @to = from, to
      from.beginning_of_day..to.end_of_day
    end

    def parse_date(raw)
      Date.iso8601(raw.to_s) if raw.present?
    rescue Date::Error
      nil
    end

    # Operadores, resultados e credores oferecidos nos filtros: só os dos credores visíveis (R78). O mesmo nome de resultado em dois credores
    # aparece com o credor ao lado.
    def load_filter_options
      @tenants = Tenant.where(id: @tenant_ids).order(:name).pluck(:name, :id)
      @operators = User.where(id: Membership.where(tenant_id: @tenant_ids).select(:user_id)).order(:name).pluck(:name, :id)
      results = ContactResult.where(tenant_id: @tenant_ids).includes(:tenant).order(:name)
      @result_options = results.map { |result| [ @several_tenants ? "#{result.name} (#{result.tenant.name})" : result.name, result.id ] }
    end
end
