module Settings
  module Segments
    # "Mover para cima" e "Mover para baixo" (R149), sem arrastar, com conferência do impacto.
    class MovementsController < ApplicationController
      include SegmentReview

      def create
        segment = Segment.find(params[:segment_id])
        authorize segment, :update?
        direction = params.expect(movement: [ :direction ])[:direction]
        return head(:unprocessable_content) unless %w[up down].include?(direction)

        render_review(::Segments::Proposal.current(segment.tenant).with_moved(segment.id, direction))
      end
    end
  end
end
