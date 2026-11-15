# Colunas da régua (21, R430): incluir e tirar (a coluna não se edita). Na régua ligada, passam pela conferência (R442).
module Cadences
  class ColumnsController < ApplicationController
    include CadenceAccess

    before_action :set_cadence

    def new
      @minimum = Catalog.min_offset(@cadence.milestone)
    end

    def create
      offset = params.expect(column: [ :offset ])[:offset].to_s.strip
      change([ { "op" => "add_column", "offset" => Integer(offset, exception: false) } ], notice: t(".done"))
    end

    def destroy = change([ { "op" => "remove_column", "column_id" => params[:id].to_i } ], notice: t(".done"))
  end
end
