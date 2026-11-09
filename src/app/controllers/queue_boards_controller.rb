# Visão das filas (15, R357): por fila, disponíveis, em atendimento e aguardando; numa fila, os sujeitos em ordem, com o item, a posição e os
# valores da ordem; por operador, a entrega aberta. Permissão 21, no credor escolhido; o RLS deixa o supervisor de uma operação ver só o
# que está pra ela.
class QueueBoardsController < ApplicationController
  before_action :set_tenant

  def index
    @queues = WorkQueue.where(tenant: @tenant, active: true, delivers: true).order(:subject, :position).to_a
    now = Time.current
    @available = QueuePlacement.where(work_queue_id: @queues.map(&:id)).where("available_at IS NULL OR available_at <= ?", now).group(:work_queue_id).count
    @waiting = QueuePlacement.where(work_queue_id: @queues.map(&:id)).where("available_at > ?", now).group(:work_queue_id).count
    @open = QueueDelivery.open.where(tenant: @tenant).includes(:user, :work_queue).order(:delivered_at).to_a
    @in_service = @open.group_by(&:work_queue_id).transform_values(&:size)
    @grouped = QueueGroupQueue.where(work_queue_id: @queues.map(&:id)).distinct.pluck(:work_queue_id)
    @cable = [ { channel: "QueuesChannel", tenant_id: @tenant.id } ].to_json
  end

  def show
    @queue = WorkQueue.find_by!(tenant: @tenant, id: params[:id])
    @placements = Pagination.new(QueuePlacement.where(work_queue_id: @queue.id).order(:rank), page: params[:pagina], per_page: params[:por_pagina])
    ids = @placements.records.map(&:subject_id)
    @names = @queue.subject == "customers" ? Customer.where(id: ids).pluck(:id, :name).to_h : Contract.where(id: ids).pluck(:id, :code).to_h
    @open = QueueDelivery.open.where(work_queue_id: @queue.id, subject_id: ids).includes(:user).index_by(&:subject_id)
    @cable = [ { channel: "QueuesChannel", tenant_id: @tenant.id } ].to_json
  end

  private
    def set_tenant
      tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_queues")).order(:name)
      @tenant = tenants.find_by(id: params[:credor]) || tenants.first or raise Pundit::NotAuthorizedError
      @tenants = tenants
      authorize WorkQueue.new(tenant: @tenant), :update?
    end
end
