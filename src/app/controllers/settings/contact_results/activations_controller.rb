module Settings
  module ContactResults
    # Desativar (R67: o resultado usado nunca se apaga) e reativar um resultado de acionamento.
    class ActivationsController < ApplicationController
      before_action :set_result

      def create = change(true)

      def destroy = change(false)

      private
        def set_result
          @result = ContactResult.find(params[:contact_result_id])
          authorize @result, :update?
        end

        def change(active)
          Contacts::ResultManager.new(Current.user).set_active(@result, active)
          redirect_to settings_contact_results_path, notice: t(active ? "settings.contact_results.activations.create.done" : "settings.contact_results.activations.destroy.done", name: @result.name),
                                                     status: :see_other
        end
    end
  end
end
