class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization
  include DemoMode
  include PanelResponses

  # Só navegadores modernos: imagens webp, notificações, selos, importmap, aninhamento de CSS e :has (decisão 0020).
  allow_browser versions: :modern

  # Mudanças no importmap invalidam o etag das respostas HTML.
  stale_when_importmap_changes

  helper_method :htmx_fragment?

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
    next panel_refuse(request.referer.presence || summary_path, error.message) if panel_request?

    redirect_back_or_to summary_path, alert: error.message, status: :see_other
  end

  # Ações pedidas pela SPA (decisão 0025): as ações do servidor que terminam redirecionando com um aviso respondem o aviso em JSON, com 422 quando
  # é recusa (`alert`). A regra fica no controlador de sempre; muda só a resposta. O GET continua redirecionando (endereços antigos que levam à casca).
  def redirect_to(options = {}, response_options = {})
    return super unless request.format.json? && !request.get?

    alerta = response_options[:alert]
    # O que aparece uma vez só (a senha temporária, R37; o segredo do webhook) vai na resposta, como ia no aviso da página.
    senha = flash[:temporary_password]
    segredo = flash[:webhook_secret]
    flash.delete(:temporary_password)
    flash.delete(:webhook_secret)
    # O destino vai junto: a tela decide se abre (a exportação de dados abre a página para imprimir).
    render json: { mensagem: alerta || response_options[:notice], tom: alerta ? "danger" : "success", destino: url_for(options), senha_temporaria: senha, segredo: segredo }.compact,
           status: alerta ? :unprocessable_content : :ok
  end

  # Do mesmo jeito, a recusa que volta ao formulário (422) responde em JSON com a mensagem: a de `@error` ou os erros do registro do formulário. A tela a
  # mostra dentro do formulário.
  def render(*arguments, **options, &block)
    return super unless request.format.json? && !options.key?(:json) && options[:status].in?([ :unprocessable_content, 422 ])

    registro = view_assigns.values.find { |valor| valor.respond_to?(:errors) && valor.errors.respond_to?(:full_messages) && valor.errors.any? }
    erro = @error.is_a?(Hash) ? @error[:message] : @error
    super(json: { mensagem: erro.presence || registro&.errors&.full_messages&.to_sentence || t("errors.messages.invalid") }, status: :unprocessable_content)
  end

  private
    # Acesso recusado ou registro de outro credor: a mesma página de "não encontrado" do resto do sistema, dentro do layout do app
    # (sem revelar se o registro existe). Pedido do htmx recebe só o código, e o navegador mostra o aviso (application.js).
    def render_not_found
      return head :not_found if request.headers["HX-Request"].present? && request.headers["HX-Boosted"].blank?
      # Pedido de dados da SPA (decisão 0025): só o código; a tela diz "não encontrado".
      return head :not_found unless request.format.html?

      @status = 404
      @request_id = request.request_id
      render "errors/show", status: :not_found, layout: authenticated? ? "application" : "erro"
    end

    # Com senha temporária, a casca mostra a definição de senha (R38); páginas do servidor levam à casca e pedidos de dados são recusados.
    def require_password_change
      return unless Current.user&.temporary_password?

      request.format.html? ? redirect_to(root_path) : head(:forbidden)
    end

    def pundit_user = Current.user

    # Pedido do htmx por um trecho (e não a página inteira): o `hx-boost` troca a página toda e vem marcado como `HX-Boosted`.
    def htmx_fragment? = request.headers["HX-Request"].present? && request.headers["HX-Boosted"].blank?
end
