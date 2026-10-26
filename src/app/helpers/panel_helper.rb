# Painel compartilhado (design system, revisão 4, decisão 0022): UM <dialog> no layout, em duas apresentações (modal de 400 px e painel lateral de 480 px).
# O botão ou link de abrir pede ao servidor o formulário (htmx, `hx-get`); o servidor devolve só o conteúdo, no layout `painel`, quando o pedido vem do painel;
# sem JavaScript, o mesmo endereço abre como página inteira. Documentação: MDN, elemento <dialog> (`showModal`, `::backdrop`) e Rails Guides, Layouts and Rendering.
module PanelHelper
  # Link com cara de botão que abre o painel. Sem JavaScript é um link comum para a mesma rota, que responde como página.
  def abrir_painel(rotulo, url, variante: nil, tamanho: nil, **html)
    dados = { variant: variante, size: tamanho }.compact.merge(html.delete(:data) || {})
    link_to rotulo, url, class: "botao", data: dados, "hx-get": url, "hx-target": "#painel-conteudo", "hx-swap": "innerHTML", "hx-push-url": "false", **html
  end

  # Formulário de painel: cabeçalho com o título, corpo com os campos e rodapé com Cancelar e a ação. Como painel (pedido do htmx) leva `hx-<método>` para o
  # `#painel-conteudo`, para que o 422 refaça o formulário dentro do painel; como página (sem JavaScript) é um cartão com a barra de página e um link de voltar.
  # `variante`: :drawer (480 px) ou :modal (400 px; `tamanho: :medio` alarga para 36 rem). `erro` é a mensagem do servidor; o bloco recebe o construtor do formulário.
  def formulario_de_painel(titulo:, url:, enviar:, descricao: nil, metodo: :post, escopo: nil, variante: :drawer, tamanho: nil, perigoso: false, erro: nil, voltar: nil, &campos)
    content_for :title, titulo
    content_for :painel_variante, variante.to_s
    content_for :painel_tamanho, tamanho.to_s if tamanho
    como_painel = panel_request?
    atributos = como_painel ? { "hx-post": url, "hx-target": "#painel-conteudo", "hx-swap": "innerHTML", "hx-push-url": "false" } : { "hx-boost": "false" }

    formulario = form_with(url: url, method: metodo, scope: escopo, class: "painel", html: atributos) do |form|
      cabecalho = como_painel ? tag.header(safe_join([ tag.div(safe_join([ tag.h2(titulo, id: "painel-titulo"), (tag.p(descricao) if descricao) ].compact)), botao_de_fechar_painel ])) : nil
      corpo = tag.div(safe_join([ (aviso(tom: :danger) { tag.p erro } if erro), (capture(form, &campos) if campos) ].compact))
      cancelar = como_painel ? tag.button("Cancelar", type: "button", command: "close", commandfor: "painel", data: { variant: "secondary" }) : link_to("Cancelar", voltar || root_path, class: "botao", data: { variant: "secondary" })
      rodape = tag.footer(safe_join([ cancelar, (tag.button(enviar, type: "submit", data: { variant: (perigoso ? "danger" : nil) }.compact) if enviar) ].compact))
      safe_join([ cabecalho, corpo, rodape ].compact)
    end
    return formulario if como_painel

    safe_join([ pagina(titulo, subtitulo: descricao), tag.section(formulario, class: "cartao", data: { formulario: true }) ])
  end

  # Confirmação curta de uma ação destrutiva ou sem dados (modal pequeno): o botão abre `/confirmacao/<token>`, onde o token é assinado e leva o título, a mensagem
  # e o destino do envio (nada que o navegador escolha). A autorização continua na ação de destino. Mesmo mecanismo do painel, sem uma rota nova por ação.
  def confirmar_no_painel(rotulo, titulo:, mensagem:, acao:, url:, metodo: :post, perigoso: true, variante: (perigoso ? "danger-outline" : "secondary"), tamanho: nil, **html)
    carga = { titulo: titulo, mensagem: mensagem, acao: acao, url: url, metodo: metodo, perigoso: perigoso }
    token = Confirmation.sign(carga)
    abrir_painel rotulo, confirmation_path(token), variante: variante, tamanho: tamanho, **html
  end

  def botao_de_fechar_painel
    tag.button(icone("x-mark"), type: "button", command: "close", commandfor: "painel", data: { variant: "link" }, "aria-label": "Fechar o painel")
  end
end
