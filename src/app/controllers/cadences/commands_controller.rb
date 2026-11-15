# Comandos (21, R441): a lista do credor, filtrada por régua, estado e tipo, com os itens e o retorno de cada um.
module Cadences
  class CommandsController < ApplicationController
    include CadenceAccess

    def index
      authorize Cadence, :index?
      @tenants = manageable_tenants
      @tenant = @tenants.find_by(id: params[:credor]) || @tenants.first or raise Pundit::NotAuthorizedError
      @cadences = Cadence.where(tenant: @tenant).by_priority
      scope = CadenceCommand.where(tenant: @tenant).includes(:recipient, action: %i[message_piece queue_task], round: :cadence, items: { decision: %i[contract bill] })
                            .order(created_at: :desc, id: :desc)
      scope = scope.where(cadence_round_id: CadenceRound.where(cadence_id: params[:regua]).select(:id)) if params[:regua].present?
      @state = FilterValue.from_url(params[:estado].to_s).presence_in(CadenceCommand::STATES.values)
      @kind = FilterValue.from_url(params[:tipo].to_s).presence_in(Catalog::KINDS)
      scope = scope.where(state: @state) if @state
      scope = scope.where(kind: @kind) if @kind
      @pagination = Pagination.new(scope, page: params[:pagina], per_page: params[:por_pagina])
      @commands = @pagination.records.to_a
      render partial: "cadences/commands/result" if fragment?
    end
  end
end
