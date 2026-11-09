# Sino de avisos do usuário (A5): lista os não lidos e marca como lido. Só os avisos de quem está logado (a busca parte do usuário).
# A janela do sino (aberta pela casca) lista os não lidos; o contador da barra vem do `menu.json` e do canal do usuário.
class NoticesController < ApplicationController
  def index; end

  def update
    Current.user.notices.find(params[:id]).read!
    return head(:no_content) if spa?

    redirect_back_or_to(root_path, status: :see_other)
  end
end
