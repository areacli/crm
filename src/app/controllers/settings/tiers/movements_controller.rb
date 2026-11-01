module Settings
  module Tiers
    # Mover um item para cima ou para baixo (R266): o "Demais" fica sempre por último. Leva à conferência do impacto.
    class MovementsController < ApplicationController
      include TierReview

      def create
        tier = Tier.find(params[:tier_id])
        authorize tier, :rearrange?
        direction = params.expect(movement: [ :direction ])[:direction]
        return head(:unprocessable_content) unless %w[up down].include?(direction)

        render_review(::Tiers::Proposal.current(tier.tenant).with_moved(tier.id, direction))
      end
    end
  end
end
