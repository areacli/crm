# Guarda de dados (07, R138): o prazo vigente e onde ele muda, a anonimização prevista nos próximos 30 dias (com "reter"), os retidos (com
# "desfazer") e as últimas execuções da tarefa diária. Só os credores em que a pessoa tem a permissão 13 (R140a, MT-5); a página se refaz
# pela SPA a cada evento do WebSocket.
class DataRetentionsController < ApplicationController
  WINDOW_DAYS = 30

  def show
    authorize :retention, :show?, policy_class: RetentionPolicy
    @tenant_ids = Current.user.tenant_ids_with("handle_data_subject_rights")
    @tenants = Tenant.where(id: @tenant_ids).order(:name)
    @several_tenants = @tenants.size > 1
    visible = params[:credor].present? && @tenant_ids.include?(params[:credor].to_i) ? [ params[:credor].to_i ] : @tenant_ids
    @settings = TenantSetting.where(tenant_id: visible).includes(:tenant).order(:tenant_id)
    @forecast = Pagination.new(Titular::Retention.due(visible, within: WINDOW_DAYS).includes(:tenant).order("due_on, id"), page: params[:pagina], per_page: params[:por_pagina])
    @retained = Pagination.new(Customer.retained.where(tenant_id: visible).includes(:tenant, :retained_by).order(:retained_at, :id), page: params[:pagina_retida], per_page: params[:por_pagina])
    @runs = TaskRun.where(tenant_id: visible, name: Titular::RetentionRun::NAME).includes(:tenant).recent.limit(10)
    @can_view_customer = Current.user.tenant_ids_with("view_portfolio")
    @can_change_period = Current.user.tenant_ids_with("change_settings")
    render partial: "data_retentions/page" if fragment?
  end
end
