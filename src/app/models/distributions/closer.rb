module Distributions
  # Encerrar distribuições (14, R311, R317): pelo fim do período, pelo recolhimento, pelo fim do credenciamento, pela regra (o contrato saiu do
  # segmento) ou por uma distribuição à mão que vence a da regra (R344). Nos contratos que deixam de estar pra a operação, as propostas de acordo
  # dela ainda não aceitas são canceladas com o motivo; promessas e acordos aceitos continuam pra ela (retenção, OP-11), salvo se o gestor
  # recolher também o que é dela (`release_retention`).
  class Closer
    PROPOSAL_STATES = %w[pending approved].freeze

    def initialize(actor) = @actor = actor

    def close_all(accreditation, reason:, note: nil)
      scope = Distribution.open.where(tenant_id: accreditation.tenant_id, operation_id: accreditation.operation_id)
      scope.find_each { |distribution| close(distribution, reason: reason, note: note, rebuild: false) }
      Operations::ReachBuilder.new(accreditation.tenant).rebuild
    end

    def close(distribution, reason:, note: nil, release_retention: false, rebuild: true)
      Operations::Context.system do
        ApplicationRecord.transaction do
          distribution.update!(ended_at: Time.current, end_reason: reason, end_note: note, release_retention: release_retention)
          Change.record!(distribution, "ended", tenant_id: distribution.tenant_id, actor: @actor, origin: @actor ? "screen" : "task", field: "end_reason", after: reason, note: note)
          cancel_proposals(distribution, reason)
        end
      end
      Operations::ReachBuilder.new(distribution.tenant).rebuild if rebuild
    end

    private
      # Contratos que esta distribuição cobria e nenhuma outra distribuição aberta da mesma operação cobre.
      def contracts_left(distribution)
        covered = Distributor.contract_ids_for(distribution)
        still = Distribution.open.where(tenant_id: distribution.tenant_id, operation_id: distribution.operation_id).where.not(id: distribution.id)
                            .flat_map { |other| Distributor.contract_ids_for(other) }
        covered - still
      end

      def cancel_proposals(distribution, reason)
        contracts = contracts_left(distribution)
        return if contracts.empty?

        text = I18n.t("distributions.end_reasons.#{reason}", default: reason)
        Agreement.where(tenant_id: distribution.tenant_id, operation_id: distribution.operation_id, state: PROPOSAL_STATES)
                 .where(id: AgreementBill.where(contract_id: contracts).select(:agreement_id)).find_each do |agreement|
          Agreements::Canceller.new(@actor).cancel(agreement, I18n.t("distributions.proposal_canceled", reason: text))
        rescue Agreements::Refused
          next
        end
      end
  end
end
