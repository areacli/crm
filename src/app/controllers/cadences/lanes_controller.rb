# Raias da régua (21, R431): incluir antes da trilha padrão, mover e tirar. Na régua ligada, passam pela conferência (R442).
module Cadences
  class LanesController < ApplicationController
    include CadenceAccess

    before_action :set_cadence

    def new
      used = @cadence.lanes.map(&:segment_id).compact
      @segments = Segment.where(tenant: @tenant, subject: @cadence.subject, active: true).where.not(id: used).order(:name_key)
      @lanes = @cadence.lanes.reject(&:default?)
    end

    def create
      attributes = params.expect(lane: %i[segment_id at])
      change([ { "op" => "add_lane", "segment_id" => attributes[:segment_id].to_i, "at" => attributes[:at].presence&.to_i } ], notice: t(".done"))
    end

    def move = change([ { "op" => "move_lane", "lane_id" => params[:id].to_i, "to" => params[:para].to_i } ], notice: t(".done"))
    def destroy = change([ { "op" => "remove_lane", "lane_id" => params[:id].to_i } ], notice: t(".done"))
  end
end
