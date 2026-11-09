class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization
  include DemoMode
  include SpaResponses
  include PanelResponses

  # Só navegadores modernos: imagens webp, notificações, selos, importmap, aninhamento de CSS e :has (decisão 0020).
  allow_browser versions: :modern

  # Mudanças no importmap invalidam o etag das respostas HTML.
  stale_when_importmap_changes

  helper_method :fragment?

  # Com senha temporária, só a tela de definir a senha abre (R38).
  before_action :require_password_change

  # 14, R313 e R314 (decisão 0024): o papel do banco de quem age vale do começo ao fim de cada requisição; para o usuário de operação, o RLS só
  # devolve o que está pra a operação dele, em qualquer consulta desta requisição.
  around_action { |_controller, action| Operations::Context.for_user(Current.user) { action.call } }

  # Acesso recusado por falta de permissão fica registrado, com o credor do registro (R33, R42), e responde como "não encontrado",
  # sem revelar o registro.
  rescue_from Pundit::NotAuthorizedError do |error|
    AccessEvent.record("access_denied", request: request, user: Current.user, tenant_id: error.record.try(:tenant_id), details: { path: request.path })
    render_not_found
  end

  # Alteração de acesso recusada por uma regra (R41, PD7...): volta para a tela de onde veio, com a mensagem.
  rescue_from Access::Refused do |error|
    next panel_refuse(request.referer.presence || root_path, error.message) if panel_request?

    redirect_back_or_to root_path, alert: error.message, status: :see_other
  end

  private
    # Acesso recusado ou registro de outro credor: a SPA recebe só o código e mostra "Não encontrado" no lugar da tela (sem revelar se o registro existe); o
    # resto (impressão, download), a página de "não encontrado".
    def render_not_found
      return head :not_found if spa?

      @status = 404
      @request_id = request.request_id
      render "errors/show", status: :not_found, layout: "erro"
    end

    def require_password_change
      return unless Current.user&.temporary_password?

      # A SPA recebe 409 e leva a pessoa à página de definir a senha.
      spa? ? head(:conflict) : redirect_to(edit_password_path)
    end

    def pundit_user = Current.user

    # O trecho que se refaz (lista, cartão, trecho vivo): pedido da SPA com `X-CRM-Fragmento` (decisão 0028, `spa/lista`).
    def fragment? = request.headers["X-CRM-Fragmento"].present?

    # Trecho de um cartão da ficha (linha do tempo, histórico de acionamentos, promessas, acordos): pedido da SPA (decisão 0028), que troca só o cartão.
    def card_fragment? = fragment? || spa?
end
