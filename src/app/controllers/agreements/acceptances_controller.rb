module Agreements
  # Aceite registrado pelo operador (11, R220, R220a, ACD1): como o termo foi apresentado, como o aceite veio, o comprovante e quem aceitou. Formulário médio: painel lateral.
  class AcceptancesController < ApplicationController
    before_action :set_agreement

    def new
      authorize @agreement, :accept?
      load_acceptors
    end

    def create
      authorize @agreement, :accept?
      raw = params.expect(acceptance: %i[presented_channel presented_at accepted_channel accepted_at proof accepted_by_customer_id])
      input = Agreements::Acceptance::Input.new(raw[:presented_channel], parse_time(raw[:presented_at]), raw[:accepted_channel], parse_time(raw[:accepted_at]), raw[:proof], raw[:accepted_by_customer_id])
      Agreements::Acceptance.new(Current.user).call(@agreement, input)
      panel_finish(agreement_path(@agreement), notice: t(".done", number: @agreement.number), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      load_acceptors
      panel_error(error.message, agreement_path(@agreement))
    end

    private
      def set_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])

      # Quem pode aceitar: os clientes do acordo e o papel de cada um (a mesma consulta da página do acordo).
      def load_acceptors = @acceptors = Agreements::Acceptance.acceptors(@agreement)

      # Data e hora do campo `datetime-local` (horário de Brasília).
      def parse_time(text)
        return nil if text.blank?

        Time.zone.parse(text.to_s)
      rescue ArgumentError
        nil
      end
  end
end
