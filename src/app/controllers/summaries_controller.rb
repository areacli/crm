# Resumo da carteira (R23): é a entrada do sistema. Um só conjunto de totais, somado sobre os credores que o usuário pode consultar (decisão de 25/10/2026),
# com o filtro de credor (01, revisão 8): sem ele, as faixas padrão do sistema; com ele, o resumo e as faixas daquele credor. O filtro refaz só o trecho
# `#resultado` (`spa/lista`).
class SummariesController < ApplicationController
  def show
    authorize :summary, :show?
    summary = Portfolio::Summary.new(Current.user)
    @tenants = summary.tenants
    @tenant = @tenants.find { |tenant| tenant.id == params[:credor].to_i } if params[:credor].present?
    @summary = summary.totals(tenant_id: @tenant&.id)
    render partial: "summaries/result" if fragment?
  end
end
