module Agreements
  # "Calcular quitação" (11, R230): o saldo do acordo para uma data, sem os juros do parcelamento que ainda não correram. Quem tem "negociar acordos" no credor. O cálculo vale até a data dele.
  class SettlementsController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :settle?
      date = BrDate.parse(params.fetch(:settlement, {})[:on_date]) || (Date.iso8601(params.fetch(:settlement, {})[:on_date].to_s) rescue nil)
      return redirect_back_or_to(agreement_path(agreement), alert: t(".invalid_date"), status: :see_other) if date.nil? || date < Date.current

      record = AgreementSettlement.calculate!(agreement, on: date, user: Current.user)
      redirect_back_or_to agreement_path(agreement), notice: t(".done", amount: "R$ #{Money.format(record.amount_cents)}", date: I18n.l(date, format: "%d/%m/%Y")), status: :see_other
    end
  end
end
