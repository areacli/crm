# Páginas de erro do sistema: o Rails chama este controlador pelo `exceptions_app` (rota não encontrada, exceção sem tratamento,
# requisição recusada). Herda direto de `ActionController::Base` e não toca no banco nem na sessão: precisa funcionar justamente
# quando o resto está quebrado. O acesso recusado por permissão também usa o mesmo conteúdo (ApplicationController).
class ErrorsController < ActionController::Base
  STATUSES = [ 400, 403, 404, 406, 422, 429, 500, 503 ].freeze

  layout "erro"

  def show
    @status = params[:status].to_i
    @status = 500 unless STATUSES.include?(@status)
    @request_id = request.request_id

    respond_to do |format|
      format.html { render "errors/show", status: @status }
      format.any { head @status }
    end
  end
end
