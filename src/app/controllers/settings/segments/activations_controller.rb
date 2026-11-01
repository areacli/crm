module Settings
  module Segments
    # Desativar e reativar um segmento (13, R273). Usado no enquadramento, desativar passa pela conferência do impacto e o item dele sai da
    # avaliação; sem uso, vale na hora. Reativar não devolve o item ao enquadramento: o gestor o inclui de novo.
    class ActivationsController < ApplicationController
      include TierReview

      def create = change(true)
      def destroy = change(false)

      private
        def change(active)
          segment = Segment.find(params[:segment_id])
          authorize segment, :update?
          segment.active = active
          if !active && segment.used?
            render_review(::Tiers::Proposal.current(segment.tenant).with_segment(segment), back: settings_segments_path)
          else
            segment.save!
            Change.record!(tenant_id: segment.tenant_id, user: Current.user, subject_type: "segment", subject_id: segment.id, event: active ? "reactivated" : "deactivated",
                           field: "active", before: (!active).to_s, after: active.to_s, origin: "screen")
            redirect_to settings_segments_path, notice: t("segments.flash.#{active ? 'reactivated' : 'deactivated'}", name: segment.name), status: :see_other
          end
        end
    end
  end
end
