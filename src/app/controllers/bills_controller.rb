# Histórico do título (R100): versões do valor, pagamentos aplicados, estornos e divergências, em ordem de data.
class BillsController < ApplicationController
  def show
    @bill = Bill.includes(:customer, :contract, :tenant).find(params[:id])
    authorize @bill
    @history = Portfolio::BillHistory.new(@bill)
  end
end
