# O menu da casca em JSON (decisão 0028): os mesmos grupos e itens do `menu_sections`, pelas mesmas permissões (MT-4), com os contadores. Resumo, Clientes e
# Acionamentos não têm grupo no `menu_sections`, e o primeiro nível do `sidemenu` é sempre um grupo: entram em "Geral" (padrões de interface, revisão 38, P1).
class MenusController < ApplicationController
  def show
    user = Current.user
    render json: {
      grupos: helpers.menu_sections.map { |secao| { titulo: secao[:titulo] || "Geral", itens: secao[:itens].map { |item| item_json(item) } } },
      usuario: { nome: user.name, email: user.email_address, operacao: user.operation&.short_name, operacao_razao_social: user.operation&.legal_name }.compact,
      busca: user.permitted_anywhere?("view_portfolio"),
      avisos: user.notices.unread.count,
      # Na demonstração a senha dos usuários públicos não muda (o documento da demonstração do projeto).
      trocar_senha: !Demo.enabled?,
      janelas: SpaResponses::WINDOWS,
      # Aviso da sessão (a operação suspensa num credor, ao entrar; uma recusa que redirecionou): a casca mostra no canto, uma vez.
      aviso: flash[:alert] || flash[:notice], tom: ("danger" if flash[:alert]),
      canais: [ { channel: "NoticesChannel" } ]
    }.compact
  end

  private
    def item_json(item)
      { rotulo: item[:rotulo], caminho: item[:caminho], contador: item[:contador],
        subitens: item[:subitens]&.map { |sub| { rotulo: sub[:rotulo], caminho: sub[:caminho] } } }.compact
    end
end
