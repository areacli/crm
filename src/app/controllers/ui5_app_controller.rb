# Serve os módulos da aplicação OpenUI5 (decisão 0025). Públicos, sem sessão: são o código da interface, igual para todos, e a entrada precisa deles.
class Ui5AppController < ActionController::Base
  # São arquivos de script pedidos por <script src> do carregador do OpenUI5: a proteção do Rails contra JavaScript de outra origem
  # (que recusa GET de .js sem XHR) não se aplica a código público e igual para todos.
  skip_forgery_protection
  def show
    # A versão no caminho muda a cada mudança do conteúdo: o arquivo pode ficar em cache para sempre.
    response.headers["Cache-Control"] = params[:versao] == Ui5App.versao ? "public, max-age=31536000, immutable" : "no-cache"
    return render(js: Ui5App.preload) if params[:caminho] == "Component-preload.js"

    arquivo = Ui5App.arquivo(params[:caminho])
    return head :not_found unless arquivo

    send_file arquivo, type: Ui5App::TIPOS.fetch(arquivo.extname), disposition: :inline
  end
end
