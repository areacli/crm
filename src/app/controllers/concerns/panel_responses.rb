# Respostas do painel compartilhado (design system, revisão 4, decisão 0022). O botão de abrir faz `hx-get` para a rota do formulário com destino
# `#painel-conteudo`; o servidor então responde só com o conteúdo do painel, no layout `painel`. Sem JavaScript a mesma rota responde a página inteira.
# Sucesso: o painel responde 204 com `HX-Trigger` (`painel:concluido`), que fecha o painel, mostra o aviso e atualiza o trecho da página; sem JavaScript, volta à
# página com o aviso. Validação (422): o formulário é refeito dentro do painel pelo próprio destino do envio.
module PanelResponses
  extend ActiveSupport::Concern

  included do
    layout :layout_da_resposta
    helper_method :panel_request?
  end

  private
    # O pedido vem do painel quando o htmx tem o `#painel-conteudo` como destino (a abertura e o envio do formulário).
    def panel_request? = request.headers["HX-Request"].present? && request.headers["HX-Target"] == "painel-conteudo"

    def layout_da_resposta = panel_request? ? "painel" : "application"

    # Termina a ação do painel. `eventos` são os eventos de invalidação que o htmx dispara no corpo da página (`cable:contact-attempts-changed`...), para que os
    # trechos ao vivo se refaçam; `atualizar` refaz o conteúdo da página inteira (ficha, lateral e contatos) sem recarregar.
    def panel_finish(destino, notice: nil, eventos: [], atualizar: false, via_htmx: panel_request?, tom: nil, navegar: false)
      unless via_htmx
        return redirect_to(destino, status: :see_other, **(tom.to_s == "danger" ? { alert: notice } : { notice: notice }))
      end
      # Navegar: a ação muda de página (apagar o registro da página aberta); o aviso vai na sessão e o htmx faz a navegação completa.
      if navegar
        tom.to_s == "danger" ? flash[:alert] = notice : flash[:notice] = notice
        response.headers["HX-Redirect"] = destino.is_a?(String) ? destino : url_for(destino)
        return head(:no_content)
      end

      gatilhos = { "painel:concluido" => { aviso: notice, atualizar: atualizar, tom: tom }.compact }.merge(eventos.index_with { {} }).to_json
      # Cabeçalho HTTP só leva ASCII: os acentos vão escapados (\uXXXX), que o JSON do htmx desfaz.
      response.headers["HX-Trigger"] = gatilhos.gsub(/[^\x00-\x7F]/) { |char| format("\\u%04x", char.ord) }
      head :no_content
    end

    # Recusa de uma regra de domínio numa ação do painel que não tem formulário a corrigir (confirmação): fecha o painel e mostra a mensagem como erro na página.
    def panel_refuse(destino, mensagem) = panel_finish(destino, notice: mensagem, tom: "danger")

    # Recusa de uma regra de domínio numa ação com formulário: o formulário volta dentro do painel com a mensagem (422); sem painel, volta à página com o aviso.
    def panel_error(mensagem, destino, view = :new)
      return redirect_to(destino, alert: mensagem, status: :see_other) unless panel_request?

      @error = mensagem
      render view, status: :unprocessable_content
    end
end
