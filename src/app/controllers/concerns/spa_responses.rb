# Respostas da SPA em EasyUI (decisão 0028). O cabeçalho `X-CRM-Trecho` diz que o pedido veio da casca, e a view vem no layout `trecho`. Desde a fase 8 não há
# página interna do servidor: o pedido de página leva à casca.
module SpaResponses
  extend ActiveSupport::Concern

  # Telas que abrem em janela (`menu.json`), em expressões no formato do JavaScript, a mesma lista nos dois lados.
  WINDOWS = %w[^/titulos/\d+$ ^/divergencias-de-valor/\d+$ ^/design-system/(janela|lento)$ ^/configuracao/segmentos/\d+$ ^/configuracao/segmentos/glossario$].freeze

  included do
    prepend_before_action :redirect_page_to_shell
    helper_method :spa?
  end

  private
    # Toda tela interna está na SPA (fase 8): o endereço pedido como página leva à casca, com o caminho no hash (`/#/clientes/1`), e a casca abre a aba.
    # Servem página ou arquivo, e pulam este filtro, só a casca, a entrada, as impressões e os downloads (`skip_before_action`).
    def redirect_page_to_shell
      return unless request.get? && !spa? && request.format.html?

      redirect_to("/##{request.fullpath}")
    end

    def spa? = request.headers["X-CRM-Trecho"].present?

    # Gravação pedida pela SPA que termina num redirecionamento (o caminho das páginas do servidor): o `$.ajax` seguiria o 303 e receberia a página, sem aviso
    # nem atualização. Vira o fim de ação da SPA: o aviso (ou o alerta, em vermelho) e a aba de onde a ação saiu levada ao destino, como a página era levada.
    def redirect_to(options = {}, response_options = {})
      return super unless spa? && !request.get? && !request.head?

      alerta = response_options[:alert] || response_options.dig(:flash, :alert)
      aviso = response_options[:notice] || response_options.dig(:flash, :notice)
      destino = URI.parse(url_for(options))
      destino = [ destino.path, destino.query ].compact.join("?")
      spa_finish(destino, notice: alerta || aviso, eventos: [], atualizar: true, tom: (:danger if alerta), navegar: true, mesma_aba: true)
    end

    # Pedido da edição inline (`spa/inline`).
    def inline? = spa? && request.headers["X-CRM-Inline"].present?

    # Edição inline (design system, 7.1): 204 com o valor gravado, ou 422 com a mensagem para junto do campo. `atualizar`: a gravação muda mais do que o valor
    # (o contato corrigido vira outro), e a aba se refaz; `aviso` vai no canto, como no fim de um diálogo.
    def inline_finish(valor, atualizar: false, aviso: nil)
      response.headers["X-CRM-Evento"] = { valor: valor, atualizar: (true if atualizar), aviso: aviso }.compact.to_json.gsub(/[^\x00-\x7F]/) { |char| format("\\u%04x", char.ord) }
      head :no_content
    end

    def inline_refuse(mensagem) = render(json: { erro: mensagem }, status: :unprocessable_content)

    # Fim de uma ação na SPA: 204 com o aviso, a atualização e os eventos no `X-CRM-Evento`, em JSON. Cabeçalho HTTP só leva ASCII: os acentos vão escapados.
    # `mesma_aba`: o destino toma o lugar da tela na aba de onde a ação saiu (a conferência do impacto e a volta dela ao enquadramento), sem abrir outra aba.
    def spa_finish(destino, notice:, eventos:, atualizar:, tom:, navegar:, mesma_aba: false)
      evento = { aviso: notice, tom: tom, atualizar: atualizar || eventos.any?, navegar: (url_for(destino) if navegar), mesma_aba: (true if navegar && mesma_aba) }.compact.to_json
      response.headers["X-CRM-Evento"] = evento.gsub(/[^\x00-\x7F]/) { |char| format("\\u%04x", char.ord) }
      head :no_content
    end
end
