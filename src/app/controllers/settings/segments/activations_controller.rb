module Settings
  module Segments
    # Desativar e reativar um segmento (R155), com conferência do impacto. "Demais" não se desativa.
    class ActivationsController < ApplicationController
      include SegmentReview

      def create = change(true)
      def destroy = change(false)

      private
        def change(active)
          segment = Segment.find(params[:segment_id])
          authorize segment, :rearrange?
          render_review(::Segments::Proposal.current(segment.tenant).with_active(segment.id, active))
        end
    end
  end
end
