class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Só navegadores modernos: imagens webp, notificações, selos, importmap, aninhamento de CSS e :has (decisão 0020).
  allow_browser versions: :modern

  # Mudanças no importmap invalidam o etag das respostas HTML.
  stale_when_importmap_changes

  helper_method :htmx_fragment?

  # Com senha temporária, só a tela de definir a senha abre (R38).
  before_action :require_password_change

  # Acesso recusado por falta de permissão fica registrado, com o credor do registro (R33, R42), e responde como "não encontrado",
  # sem revelar o registro.
  rescue_from Pundit::NotAuthorizedError do |error|
    AccessEvent.record("access_denied", request: request, user: Current.user, tenant_id: error.record.try(:tenant_id), details: { path: request.path })
    head :not_found
  end

  # Alteração de acesso recusada por uma regra (R41, PD7...): volta para a tela de onde veio, com a mensagem.
  rescue_from Access::Refused do |error|
    redirect_back_or_to root_path, alert: error.message, status: :see_other
  end

  private
    def require_password_change
      redirect_to edit_password_path if Current.user&.temporary_password?
    end

    def pundit_user = Current.user

    # Pedido do htmx por um trecho (e não a página inteira): o `hx-boost` troca a página toda e vem marcado como `HX-Boosted`.
    def htmx_fragment? = request.headers["HX-Request"].present? && request.headers["HX-Boosted"].blank?
end
