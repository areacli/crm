module Settings
  module ContactResults
    # Sobe ou desce um resultado na lista, sem arrastar (revisão 2).
    class MovementsController < ApplicationController
      def create
        result = ContactResult.find(params[:contact_result_id])
        authorize result, :update?
        direction = params.expect(movement: [ :direction ])[:direction]
        return head(:unprocessable_content) unless %w[up down].include?(direction)

        Contacts::ResultManager.new(Current.user).move(result, direction)
        redirect_to settings_contact_results_path(anchor: "resultado-#{result.id}"), status: :see_other
      end
    end
  end
end
