module Agreements
  # Aceite registrado pelo operador (11, R220, R220a, ACD1): como o termo foi apresentado, como o aceite veio, o comprovante e quem aceitou.
  class AcceptancesController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :accept?
      raw = params.expect(acceptance: %i[presented_channel presented_at accepted_channel accepted_at proof accepted_by_customer_id])
      input = Agreements::Acceptance::Input.new(raw[:presented_channel], parse_time(raw[:presented_at]), raw[:accepted_channel], parse_time(raw[:accepted_at]), raw[:proof], raw[:accepted_by_customer_id])
      Agreements::Acceptance.new(Current.user).call(agreement, input)
      redirect_to agreement_path(agreement), notice: t(".done", number: agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to agreement_path(agreement), alert: error.message, status: :see_other
    end

    private
      # Data e hora do campo `datetime-local` (horário de Brasília).
      def parse_time(text)
        return nil if text.blank?

        Time.zone.parse(text.to_s)
      rescue ArgumentError
        nil
      end
  end
end
