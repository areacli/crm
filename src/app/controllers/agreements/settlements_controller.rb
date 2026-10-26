module Agreements
  # "Calcular quitação" (11, R230): o saldo do acordo para uma data, sem os juros do parcelamento que ainda não correram. Quem tem "negociar acordos" no credor. A data se pede num modal pequeno.
  class SettlementsController < ApplicationController
    before_action :set_agreement

    def new
      authorize @agreement, :settle?
    end

    def create
      authorize @agreement, :settle?
      raw = params.fetch(:settlement, {})[:on_date]
      date = BrDate.parse(raw) || (Date.iso8601(raw.to_s) rescue nil)
      return panel_error(t(".invalid_date"), agreement_path(@agreement)) if date.nil? || date < Date.current

      record = AgreementSettlement.calculate!(@agreement, on: date, user: Current.user)
      panel_finish(agreement_path(@agreement), notice: t(".done", amount: "R$ #{Money.format(record.amount_cents)}", date: I18n.l(date, format: "%d/%m/%Y")), atualizar: true)
    end

    private
      def set_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
