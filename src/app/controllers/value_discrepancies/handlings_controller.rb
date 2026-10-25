# Tratar uma divergência de valor (R99): nota obrigatória, e manter ou aplicar o valor informado.
module ValueDiscrepancies
  class HandlingsController < ApplicationController
    def create
      discrepancy = ValueDiscrepancy.find(params[:value_discrepancy_id])
      authorize discrepancy, :create?
      attributes = params.expect(handling: %i[note choice])
      Discrepancies::Handler.new(Current.user).call(discrepancy, note: attributes[:note], choice: attributes[:choice])
      redirect_to value_discrepancy_path(discrepancy), notice: t(".done"), status: :see_other
    rescue Discrepancies::Refused => error
      redirect_to value_discrepancy_path(discrepancy), alert: error.message, status: :see_other
    end
  end
end
