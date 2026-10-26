# Tratar uma divergência de valor (R99): nota obrigatória, e manter ou aplicar o valor informado. A nota e a escolha se pedem num modal pequeno.
module ValueDiscrepancies
  class HandlingsController < ApplicationController
    before_action :set_discrepancy

    def new
      authorize @discrepancy, :create?
    end

    def create
      authorize @discrepancy, :create?
      attributes = params.expect(handling: %i[note choice])
      Discrepancies::Handler.new(Current.user).call(@discrepancy, note: attributes[:note], choice: attributes[:choice])
      panel_finish(value_discrepancy_path(@discrepancy), notice: t(".done"), atualizar: true)
    rescue Discrepancies::Refused => error
      panel_error(error.message, value_discrepancy_path(@discrepancy))
    end

    private
      def set_discrepancy = @discrepancy = ValueDiscrepancy.includes(:bill, :tenant).find(params[:value_discrepancy_id])
  end
end
