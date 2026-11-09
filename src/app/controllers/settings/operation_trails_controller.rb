# Trilha das operações (14, R320, R325): o que os usuários de operação abriram, buscaram, não encontraram e exportaram. Permissão 20.
module Settings
  class OperationTrailsController < ApplicationController
    def index
      tenant_ids = Current.user.tenant_ids_with("view_operation_trail")
      raise Pundit::NotAuthorizedError if tenant_ids.empty?

      skip_authorization
      scope = OperationTrailEvent.where(tenant_id: tenant_ids).includes(:operation, :user, :customer).order(created_at: :desc)
      scope = scope.where(operation_id: params[:operacao]) if params[:operacao].present?
      scope = scope.where(user_id: params[:usuario]) if params[:usuario].present?
      kind = FilterValue.from_url(params[:tipo])
      scope = scope.where(kind: kind) if OperationTrailEvent::KINDS.include?(kind)
      scope = scope.where(created_at: Date.iso8601(params[:de]).beginning_of_day..) if params[:de].present?
      scope = scope.where(created_at: ..Date.iso8601(params[:ate]).end_of_day) if params[:ate].present?
      @operations = Operation.joins(:accreditations).where(accreditations: { tenant_id: tenant_ids }).distinct.order(:short_name).pluck(:short_name, :id)
      @users = User.where(id: OperationTrailEvent.where(tenant_id: tenant_ids).select(:user_id)).order(:name).pluck(:name, :id)
      @pagination = Pagination.new(scope, page: params[:pagina], per_page: params[:por_pagina])
      @events = @pagination.records
    end
  end
end
