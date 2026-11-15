# A situação na régua na ficha (21, R444): o trecho que a ficha carrega, calculado na hora para o cliente e os contratos dele. Quem vê a ficha vê;
# o usuário de operação vê só o que está pra ele (RLS).
module Customers
  class CadenceSituationsController < ApplicationController
    def show
      @customer = Customer.find(params[:customer_id])
      authorize @customer, :show?
      @rows = Cadences::Situation.for(@customer)
      render partial: "customers/cadence_situation", locals: { rows: @rows, customer: @customer }
    end
  end
end
