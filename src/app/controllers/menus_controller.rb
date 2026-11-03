# O menu da casca em JSON (decisão 0025): os mesmos grupos e itens do menu lateral, pelas mesmas permissões (MT-4), com os contadores
# e o número de avisos não lidos do sino. O "Próximo" (15, R353) saiu da casca a pedido do Paulo (02/11/2026) até decidirmos onde ele fica.
class MenusController < ApplicationController
  def show
    user = Current.user
    render json: {
      secoes: helpers.menu_sections.map { |secao| { titulo: secao[:titulo], itens: secao[:itens].map { |item| item_json(item) } } },
      busca: user.permitted_anywhere?("view_portfolio"),
      avisos: user.notices.unread.count
    }
  end

  private
    def item_json(item)
      { rotulo: item[:rotulo], caminho: item[:caminho], contador: item[:contador],
        subitens: item[:subitens]&.map { |sub| { rotulo: sub[:rotulo], caminho: sub[:caminho] } } }.compact
    end
end
