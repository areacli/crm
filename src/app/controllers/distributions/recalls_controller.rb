# Recolher uma distribuição antes do fim (14, R311, R317): motivo de uma lista; "recolher também o que é dela" tira da operação as promessas e
# os acordos que ela fez nestes contratos (que continuam valendo para o cliente).
module Distributions
  class RecallsController < ApplicationController
    before_action :set_distribution

    def new
    end

    def create
      attributes = params.expect(recall: %i[reason note release_retention])
      reason = attributes[:reason].presence_in(Distribution::RECALL_REASONS) or return refuse(t("operations.refused.reason_required"))
      return refuse(t("operations.refused.reason_required")) if reason == "other" && attributes[:note].blank?

      Distributions::Closer.new(Current.user).close(@distribution, reason: reason, note: attributes[:note].to_s.strip.first(300).presence,
                                                                   release_retention: attributes[:release_retention] == "1")
      panel_finish(distributions_path, notice: t(".done", target: @distribution.target_label), atualizar: true)
    end

    private
      def set_distribution
        @distribution = policy_scope(Distribution).open.includes(:operation, :customer, :contract).find(params[:distribution_id])
        authorize @distribution, :update?
      end

      def refuse(message)
        @error = message
        render :new, status: :unprocessable_content
      end
  end
end
