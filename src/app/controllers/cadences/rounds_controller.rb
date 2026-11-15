# Rodadas de uma régua (21, R435, R439): toda hora prevista, inclusive as que não rodaram, com as contagens que se atualizam com os retornos, e o
# detalhe de cada uma por raia, coluna, ação e motivo.
module Cadences
  class RoundsController < ApplicationController
    include CadenceAccess

    before_action :set_cadence

    def index
      scope = @cadence.rounds.order(scheduled_for: :desc)
      @pagination = Pagination.new(scope, page: params[:pagina], per_page: params[:por_pagina])
      @rounds = @pagination.records.to_a
      @counts = RoundCounts.new(@rounds)
      @cable = cable
      render partial: "cadences/rounds/result" if fragment?
    end
  end
end
