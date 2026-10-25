# Resumo da carteira de cada credor (R23): é a entrada do sistema.
class SummariesController < ApplicationController
  def show
    authorize :summary, :show?
    @summaries = Portfolio::Summary.new(Current.user).per_tenant
  end
end
