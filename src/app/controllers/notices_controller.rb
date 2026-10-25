# Sino de avisos do usuário (A5): lista os não lidos e marca como lido. Só os avisos de quem está logado (a busca parte do usuário).
# O sino se refaz pelo htmx quando o WebSocket avisa que há aviso novo (`cable:notice-created`).
class NoticesController < ApplicationController
  def index
    return redirect_to root_path unless htmx_fragment?

    render partial: "notices/bell"
  end

  def update
    Current.user.notices.find(params[:id]).read!
    htmx_fragment? ? render(partial: "notices/bell") : redirect_back_or_to(root_path, status: :see_other)
  end
end
