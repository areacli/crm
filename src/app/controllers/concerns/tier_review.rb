# Conferência do impacto (13, R272, R291): toda mudança no enquadramento financeiro, num segmento usado nele ou nos parâmetros de encargos do
# credor mostra, antes de valer, quantos contratos e quanto saldo entram e saem de cada item e a diferença do valor atualizado. Nada é gravado
# aqui; "Confirmar mudança" leva a proposta assinada à confirmação.
module TierReview
  extend ActiveSupport::Concern

  private
    # A conferência roda em segundo plano (revisão 3): a página abre com "Conferindo…" e se completa quando o WebSocket avisa.
    def render_review(proposal, before: nil, back: nil)
      changes = Tiers::Changes.describe(before || Tiers::Proposal.current(proposal.tenant), proposal)
      id = Tiers::Review.start(proposal, back: back || settings_tiers_path, changes: changes)
      url = settings_tier_review_path(id)
      return redirect_to(url, status: :see_other) unless request.headers["HX-Request"]

      # Do painel ("Incluir segmento") ou de outro pedido do htmx: navegação completa para a página da conferência.
      response.headers["HX-Redirect"] = url
      head :no_content
    end

    def tenant_for_change(id)
      tenant = Tenant.find(id)
      authorize Tier.new(tenant: tenant), :create?
      tenant
    end
end
