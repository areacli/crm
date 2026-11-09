module Settings
  # A página da conferência do impacto (13, R291): "Conferindo…" até o cálculo terminar, depois o resultado na ordem da R291 e o rodapé com
  # "Confirmar mudança", "Voltar e editar" e "Descartar". Pedida pela SPA (aviso do WebSocket), devolve só o trecho do resultado.
  class TierReviewsController < ApplicationController
    def show
      @review = ::Tiers::Review.fetch(params[:id])
      return redirect_to(settings_tiers_path, alert: t("tiers.errors.invalid_token"), status: :see_other) unless @review

      @tenant = Tenant.find(@review["tenant_id"])
      authorize Tier.new(tenant: @tenant), :create?
      @id = params[:id]
      render partial: "settings/tier_reviews/result", locals: { review: @review, id: @id, tenant: @tenant } if fragment?
    end
  end
end
