class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Só navegadores modernos: imagens webp, notificações, selos, importmap, aninhamento de CSS e :has (decisão 0020).
  allow_browser versions: :modern

  # Mudanças no importmap invalidam o etag das respostas HTML.
  stale_when_importmap_changes

  helper_method :htmx_fragment?

  # Acesso recusado por falta de permissão fica registrado (R33) e responde como "não encontrado", sem revelar o registro.
  rescue_from Pundit::NotAuthorizedError do
    AccessEvent.record("access_denied", request: request, user: Current.user, details: { path: request.path })
    head :not_found
  end

  private
    def pundit_user = Current.user

    # Pedido do htmx por um trecho (e não a página inteira): o `hx-boost` troca a página toda e vem marcado como `HX-Boosted`.
    def htmx_fragment? = request.headers["HX-Request"].present? && request.headers["HX-Boosted"].blank?
end
