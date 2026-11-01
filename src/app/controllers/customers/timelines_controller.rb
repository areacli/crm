module Customers
  # Linha do tempo da ficha (padrões de interface, revisão 24): o trecho do cartão, trocado pelo htmx no filtro e na paginação. Sem JavaScript,
  # os links levam à ficha com os mesmos parâmetros.
  class TimelinesController < ApplicationController
    def show
      @customer = Customer.includes(:tenant).find(params[:customer_id])
      authorize @customer, :show?
      return redirect_to(customer_path(@customer, **timeline_params)) unless htmx_fragment?

      contract = @customer.contracts.find_by(id: params[:contrato]) if params[:contrato].present?
      timeline = CustomerTimeline.new(@customer, contract: contract, kind: params[:linha], page: params[:linha_pagina], distributions: !Operations::Context.operation?)
      render partial: "customers/timeline", locals: { customer: @customer, timeline: timeline, base: timeline_params.slice(:aba, :contrato) }
    end

    private
      def timeline_params = { aba: params[:aba].presence, contrato: params[:contrato].presence, linha: params[:linha].presence, linha_pagina: params[:linha_pagina].presence }.compact
  end
end
