# O que as telas da régua têm em comum (21, R442, R445): a régua do credor em que o usuário tem "configurar régua" (24), e a mudança, que vale na
# hora na régua desligada e passa pela conferência na ligada (menos desligar) e ao ligar.
module CadenceAccess
  extend ActiveSupport::Concern

  private
    def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with(CadencePolicy::KEY)).order(:name)

    def set_cadence
      @cadence = Cadence.includes(:tenant).find(params[:cadence_id] || params[:id])
      authorize @cadence, :update?
      @tenant = @cadence.tenant
    end

    def cable = [ { channel: "CadencesChannel", tenant_id: @tenant.id } ].to_json

    def change(operations, notice:)
      if Cadences::Editor.needs_review?(@cadence, operations)
        token = Cadences::Proposal.new(@cadence, operations).token
        CadenceReviewJob.perform_later(@tenant, token, requested_by: Current.user)
        panel_finish(review_cadence_path(@cadence, token: token), navegar: true, mesma_aba: true)
      else
        Cadences::Editor.new(@cadence, actor: Current.user).apply!(operations)
        CadencesChannel.broadcast_to(@tenant, { event: "cadences-changed" })
        panel_finish(cadence_path(@cadence), notice: notice, navegar: true, mesma_aba: true)
      end
    rescue Cadences::Editor::Invalid, Cadences::Refused => error
      panel_refuse(cadence_path(@cadence), error.message)
    end
end
