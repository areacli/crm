# Ações de uma célula (21, R432, R433): o painel escolhe o tipo e, depois, o parâmetro do tipo (a peça, a condição, o meio, a tarefa). Incluir e tirar;
# na régua ligada, passam pela conferência (R442).
module Cadences
  class CellsController < ApplicationController
    include CadenceAccess

    before_action :set_cadence

    def new
      @lane = @cadence.lanes.find { |lane| lane.id == params[:raia].to_i } or return head(:not_found)
      @column = @cadence.columns.find { |column| column.id == params[:coluna].to_i } or return head(:not_found)
      @kind = Catalog::KINDS.include?(params[:tipo]) ? params[:tipo] : nil
      @pieces = MessagePiece.where(tenant: @tenant, active: true, channel: Catalog::COMMUNICATIONS[@kind]).order(:name) if @kind && Catalog.communication?(@kind)
      @tasks = QueueTask.where(tenant: @tenant, active: true).order(:name) if @kind == "task"
      @methods = Catalog.issuable_methods(@tenant) if @kind == "issue_instrument"
    end

    def create
      attributes = params.expect(cell: [ :lane_id, :column_id, :kind, :message_piece_id, :queue_task_id, :payment_method, { params: %w[form concession value due_days object reissue] } ])
      operation = { "op" => "add_action", "lane_id" => attributes[:lane_id].to_i, "column_id" => attributes[:column_id].to_i, "kind" => attributes[:kind],
                    "message_piece_id" => attributes[:message_piece_id].presence&.to_i, "queue_task_id" => attributes[:queue_task_id].presence&.to_i,
                    "payment_method" => attributes[:payment_method].presence, "params" => attributes[:params].to_h.compact_blank }
      change([ operation ], notice: t(".done"))
    end

    def destroy = change([ { "op" => "remove_action", "action_id" => params[:id].to_i } ], notice: t(".done"))
  end
end
