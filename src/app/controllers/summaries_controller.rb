# Resumo da carteira (R23): é a entrada do sistema. Um só conjunto de totais, somado sobre os credores que o usuário pode consultar (decisão de 25/10/2026).
class SummariesController < ApplicationController
  def show
    authorize :summary, :show?
    @summary = Portfolio::Summary.new(Current.user).totals
  end
end
