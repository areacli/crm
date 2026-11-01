# Trilha das operações (14, R320, R325): o que os usuários de operação abriram, buscaram, não encontraram e exportaram. Permissão 20.
module Settings
  class OperationTrailsController < ApplicationController
    def index
      tenant_ids = Current.user.tenant_ids_with("view_operation_trail")
      raise Pundit::NotAuthorizedError if tenant_ids.empty?

      skip_authorization
      scope = OperationTrailEvent.where(tenant_id: tenant_ids).includes(:operation, :user, :customer).order(created_at: :desc)
      scope = scope.where(operation_id: params[:operation]) if params[:operation].present?
      scope = scope.where(user_id: params[:user]) if params[:user].present?
      scope = scope.where(kind: params[:kind]) if OperationTrailEvent::KINDS.include?(params[:kind])
      scope = scope.where(created_at: Date.iso8601(params[:from]).beginning_of_day..) if params[:from].present?
      scope = scope.where(created_at: ..Date.iso8601(params[:to]).end_of_day) if params[:to].present?
      @operations = Operation.joins(:accreditations).where(accreditations: { tenant_id: tenant_ids }).distinct.order(:short_name).pluck(:short_name, :id)
      @users = User.where(id: OperationTrailEvent.where(tenant_id: tenant_ids).select(:user_id)).order(:name).pluck(:name, :id)
      @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
      @events = @pagination.records
    end
  end
end
