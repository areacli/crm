# Respostas das ações da SPA (decisão 0028): o diálogo, a confirmação e o formulário da aba enviam com `X-CRM-Trecho`, e a ação termina com o fim da SPA
# (`spa_finish`: 204 com o aviso e o que a tela faz depois). Sem o cabeçalho (o envio de outro cliente, os testes de regra), a mesma ação volta à página de
# destino por redirecionamento, com o aviso na sessão. Validação (422): o formulário volta com a mensagem, no layout `trecho`.
module PanelResponses
  extend ActiveSupport::Concern

  included do
    layout "trecho"
    helper_method :panel_request?
  end

  private
    def panel_request? = spa?

    # Termina a ação. `atualizar` refaz a tela de onde a ação saiu; `navegar` leva a aba (ou outra, se já aberta) ao destino; `eventos` são os avisos do tempo real
    # que a ação também dispara, e contam como atualizar.
    def panel_finish(destino, notice: nil, eventos: [], atualizar: false, tom: nil, navegar: false, mesma_aba: false)
      return spa_finish(destino, notice: notice, eventos: eventos, atualizar: atualizar, tom: tom, navegar: navegar, mesma_aba: mesma_aba) if spa?

      redirect_to(destino, status: :see_other, **(tom.to_s == "danger" ? { alert: notice } : { notice: notice }))
    end

    # Recusa de uma regra de domínio numa ação que não tem formulário a corrigir (confirmação): fecha o diálogo e mostra a mensagem como erro.
    def panel_refuse(destino, mensagem) = panel_finish(destino, notice: mensagem, tom: "danger")

    # Recusa de uma regra de domínio numa ação com formulário: o formulário volta com a mensagem (422); sem a SPA, volta à página com o aviso.
    def panel_error(mensagem, destino, view = :new)
      return redirect_to(destino, alert: mensagem, status: :see_other) unless panel_request?

      @error = mensagem
      render view, status: :unprocessable_content
    end
end
