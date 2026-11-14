# Marcação semântica do catálogo do design system (o documento do design system do projeto, seção 6 e revisão 2): ícone, situação e aviso.
module InterfaceHelper
  TONS = %w[success warning danger info neutral].freeze

  # Ícone do Lucide (design system, revisão 25; decisão 0035), em SVG embutido, na cor do texto: decorativo (aria-hidden) ou, com `rotulo`, com nome para
  # o leitor de tela. Os nomes são os do Lucide (`lib/icones.rb`); `data-icone` deixa a SPA copiar o desenho de um modelo da página.
  def icone(nome, rotulo: nil, tamanho: nil)
    atributos = { class: "icone", viewBox: "0 0 24 24", data: { icone: nome, size: tamanho }.compact }
    atributos.merge!(rotulo ? { role: "img", "aria-label": rotulo } : { "aria-hidden": "true" })
    # O desenho vem dos arquivos do Lucide na árvore, nunca de quem usa a tela.
    tag.svg(Icones.conteudo(nome).html_safe, **atributos)
  end

  # Selo de situação: o texto sempre por extenso e o tom em data-tone (nunca só cor).
  def situacao(texto, tom: :neutral)
    tom = tom.to_s
    raise ArgumentError, "tom inválido: #{tom}" unless TONS.include?(tom)

    tag.span(texto, class: "situacao", data: { tone: tom })
  end

  # Selo que explica (padrões de interface, revisão 40): o mesmo selo, num botão que abre a explicação inteira no popover do (i); o `title` a repete para quem
  # para o ponteiro em cima. Serve ao aviso que não pede ação agora e por isso não merece uma faixa.
  def situacao_com_definicao(texto, definicao, tom: :neutral)
    tom = tom.to_s
    raise ArgumentError, "tom inválido: #{tom}" unless TONS.include?(tom)

    safe_join([ tag.button(texto, type: "button", class: "situacao", title: definicao, data: { tone: tom, spa_popover: true }), tag.div(tag.p(definicao), popover: "auto", class: "definicao") ])
  end

  # Aviso em bloco com ícone: `role="alert"` para erro que bloqueia, `role="status"` nos demais.
  def aviso(tom: :info, &conteudo)
    nome_do_icone, papel = { danger: [ "circle-alert", "alert" ], warning: [ "triangle-alert", "status" ],
                             success: [ "circle-check", "status" ] }.fetch(tom.to_sym, [ "info", "status" ])
    tag.aside(class: "aviso", role: papel, data: { tone: tom }) { icone(nome_do_icone) + tag.div(&conteudo) }
  end

  # Barra de página (modelo de página, revisão 4): título, subtítulo, indicadores (selos) e as ações da página à direita. Primeiro bloco do trecho.
  def pagina(titulo, subtitulo: nil, indicadores: [], &acoes)
    tag.header(class: "cabecalho-da-pagina") do
      partes = [ tag.div { safe_join([ tag.h1(titulo), (tag.p(subtitulo) if subtitulo) ].compact) } ]
      partes << tag.div(safe_join(indicadores), class: "indicadores") if indicadores.any?
      partes << tag.div(capture(&acoes), class: "acoes") if acoes
      safe_join(partes)
    end
  end

  # Botão (i) com a definição de um indicador num popover do HTML (atributo `popover`). Não há `id` fixo em trecho (duas fichas têm a mesma marcação): o
  # `spa/navegacao` abre o popover vizinho. O `id` dos chamadores antigos fica sem uso.
  def informacao(rotulo, texto, _id = nil)
    safe_join([ tag.button(icone("info"), type: "button", class: "informacao", data: { spa_popover: true }, "aria-label": "Definição de #{rotulo}"), tag.div(tag.p(texto), popover: "auto", class: "definicao") ])
  end

  # Indicador do resumo (KPI): rótulo de 13 px, valor de 22 px, detalhe opcional e, com `definicao`, o (i) com o popover. Vai dentro de `<dl class="kpis">`.
  def kpi(rotulo, valor, detalhe: nil, definicao: nil)
    tag.div(class: "kpi") do
      safe_join([ tag.dt(safe_join([ rotulo, (informacao(rotulo, definicao) if definicao) ].compact)),
                  tag.dd(safe_join([ valor, (tag.small(detalhe) if detalhe) ].compact)) ])
    end
  end

  # Campo em linha (modelo Configuração): rótulo à esquerda (180 px) e o campo na largura do dado (`tamanho`: "numero", "data"; texto até 360 px).
  def campo_em_linha(rotulo, campo_id, ajuda: nil, tamanho: nil, &campo)
    tag.div(class: "campo", data: { disposicao: "linha", tamanho: tamanho }.compact) do
      safe_join([ tag.label(rotulo, for: campo_id), capture(&campo), (tag.small(ajuda) if ajuda) ].compact)
    end
  end

  # Política (modelo Configuração): o título à esquerda (com a ajuda em popover) e as opções à direita, em uma linha da grade; vale para escolhas e valores.
  def politica(titulo, id, ajuda: nil, &opcoes)
    tag.div(class: "politica", role: "group", "aria-labelledby": "#{id}-titulo") do
      # A última palavra vai com o (i), para ele não cair sozinho na linha de baixo (revisão das telas de 13/11/2026).
      rotulo = if ajuda
        *comeco, ultima = titulo.to_s.split(" ")
        safe_join([ (comeco.join(" ") + " " if comeco.any?), tag.span(safe_join([ ultima, " ", informacao(titulo, ajuda, "def-#{id}") ]), class: "sem-quebra") ].compact)
      else
        titulo
      end
      safe_join([ tag.span(rotulo, id: "#{id}-titulo", class: "titulo"), tag.div(capture(&opcoes), class: "opcoes") ])
    end
  end

  # Menu de linha (o botão com as reticências do Lucide): botão e popover com as ações da linha (links que abrem diálogo ou aba, ou botões de ação direta),
  # aberto pelo `spa/navegacao`. O `id` dos chamadores antigos fica sem uso.
  def menu_de_linha(_id, rotulo, &itens)
    safe_join([ tag.button(icone("ellipsis"), type: "button", class: "menu-de-linha", "aria-label": rotulo, data: { spa_popover: true }), tag.div(capture(&itens), popover: "auto", class: "menu") ])
  end

  # Linha com detalhe (padrões de interface, revisão 25, P26; design system, revisão 10): cada registro ocupa uma linha, e o resto vai numa faixa logo abaixo,
  # fechada, que abre pela seta antes do conteúdo da primeira coluna. A tabela leva `data-detalhes`, e a grade monta o detalhe pela `datagrid-detailview`.
  def alternar_detalhe(id, objeto)
    tag.button(icone("chevron-right"), type: "button", class: "alternar-detalhe", data: { alternar_detalhe: true, objeto: objeto },
               "aria-expanded": "false", "aria-controls": id, "aria-label": "Mostrar detalhes de #{objeto}")
  end

  # O botão do cabeçalho da tabela que abre e fecha todos os detalhes dela.
  def alternar_todos_os_detalhes
    tag.button(icone("chevron-right"), type: "button", class: "alternar-detalhe", data: { alternar_todos: true }, "aria-expanded": "false",
               "aria-label": "Mostrar os detalhes de todas as linhas")
  end

  # A faixa do detalhe: uma linha da tabela, na largura dela, escondida até a seta abrir.
  def detalhe_da_linha(id, colunas, &conteudo)
    tag.tr(id: id, class: "detalhe-da-linha", hidden: true) { tag.td(capture(&conteudo), colspan: colunas) }
  end

  # Texto livre longo numa célula (P26): cortado com reticências na linha, inteiro no detalhe.
  def cortado(texto) = tag.span(texto, class: "cortado", title: texto)

  # Abas da ficha: cada aba é um endereço; `itens` são [rótulo, caminho, contagem (ou nil), atual?].
  def abas_da_pagina(rotulo, itens)
    tag.nav(class: "abas", "aria-label": rotulo) do
      safe_join(itens.map do |texto, caminho, contagem, atual|
        link_to(safe_join([ texto, (tag.span(contagem, class: "selo") unless contagem.nil?) ].compact, " "), caminho, aria: { current: (atual ? "page" : nil) })
      end)
    end
  end
end
