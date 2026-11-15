module Cadences
  # Confirmação de uma mudança da régua ligada (21, R442): recusa a conferência velha e aplica as operações, com o histórico, de uma vez.
  class Applier
    def initialize(actor) = @actor = actor

    def confirm(cadence, token)
      proposal = Proposal.from_token(cadence, token)
      ApplicationRecord.transaction do
        cadence.lock!
        raise Refused, I18n.t("cadences.errors.stale") if proposal.stale?

        Editor.new(cadence, actor: @actor).apply!(proposal.operations)
      end
      CadencesChannel.broadcast_to(cadence.tenant, { event: "cadences-changed" })
      cadence
    rescue Editor::Invalid => error
      raise Refused, error.message
    end
  end
end
