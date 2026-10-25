module Settings
  # Política "Produto do contrato no segmento" (R151): muda o segmento de contratos, então passa pela conferência do impacto.
  class SegmentPoliciesController < ApplicationController
    include SegmentReview

    def update
      tenant = tenant_for_change(params[:tenant_id])
      policy = params.expect(segment_policy: [ :value ])[:value]
      return head(:unprocessable_content) unless TenantSetting.defined_enums.fetch("segment_product_policy").key?(policy)

      render_review(::Segments::Proposal.current(tenant).with_policy(policy))
    end
  end
end
