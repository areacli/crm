# Conferência do impacto (R154): toda mudança de segmentos mostra, antes de valer, quantos contratos e quanto saldo entram e saem. Nada é
# gravado aqui; o botão "Confirmar mudança nos segmentos" leva a proposta assinada à confirmação.
module SegmentReview
  extend ActiveSupport::Concern

  private
    def render_review(proposal, status: :ok)
      @proposal = proposal
      @tenant = proposal.tenant
      @impact = Segments::Impact.new(proposal)
      @charges_impact = Charges::Impact.new(proposal)
      @token = proposal.token
      render "settings/segment_confirmations/show", status: status
    end

    def tenant_for_change(id)
      tenant = Tenant.find(id)
      authorize Segment.new(tenant: tenant), :create?
      tenant
    end
end
