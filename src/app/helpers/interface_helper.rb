# Marcação semântica do catálogo do design system (o documento do design system do projeto, seção 6 e revisão 2): ícone, situação e aviso.
module InterfaceHelper
  # Heroicons (outline 24, licença MIT) em SVG embutido: o conjunto fica na árvore, sem CDN e sem JavaScript.
  ICONES = {
    "x-mark" => "M6 18 18 6M6 6l12 12",
    "bars-3" => "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5",
    "chevron-down" => "m19.5 8.25-7.5 7.5-7.5-7.5",
    "chevron-up" => "m4.5 15.75 7.5-7.5 7.5 7.5",
    "check-circle" => "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "exclamation-circle" => "M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z",
    "exclamation-triangle" => "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z",
    "information-circle" => "m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z",
    "magnifying-glass" => "m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z",
    "bell" => "M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"
  }.freeze

  TONS = %w[success warning danger info neutral].freeze

  # Ícone decorativo (aria-hidden) ou, com `rotulo`, com nome para o leitor de tela.
  def icone(nome, rotulo: nil, tamanho: nil)
    caminho = ICONES.fetch(nome.to_s)
    atributos = { class: "icone", viewBox: "0 0 24 24", data: { size: tamanho }.compact }
    atributos.merge!(rotulo ? { role: "img", "aria-label": rotulo } : { "aria-hidden": "true" })
    tag.svg(**atributos) { tag.path(d: caminho) }
  end

  # Selo de situação: o texto sempre por extenso e o tom em data-tone (nunca só cor).
  def situacao(texto, tom: :neutral)
    tom = tom.to_s
    raise ArgumentError, "tom inválido: #{tom}" unless TONS.include?(tom)

    tag.span(texto, class: "situacao", data: { tone: tom })
  end

  # Aviso em bloco com ícone: `role="alert"` para erro que bloqueia, `role="status"` nos demais.
  def aviso(tom: :info, &conteudo)
    nome_do_icone, papel = { danger: [ "exclamation-circle", "alert" ], warning: [ "exclamation-triangle", "status" ],
                             success: [ "check-circle", "status" ] }.fetch(tom.to_sym, [ "information-circle", "status" ])
    tag.aside(class: "aviso", role: papel, data: { tone: tom }) { icone(nome_do_icone) + tag.div(&conteudo) }
  end

  # Barra de página (modelo de página, revisão 4): título, subtítulo, indicadores (selos) e as ações da página à direita. Primeiro bloco do `main`.
  # `vivo: { url:, eventos: [...] }` refaz só os indicadores quando um evento de invalidação chega (o chip de promessas da ficha), sem recarregar a página.
  def pagina(titulo, subtitulo: nil, indicadores: [], vivo: nil, &acoes)
    tag.header(class: "cabecalho-da-pagina") do
      partes = [ tag.div { safe_join([ tag.h1(titulo), (tag.p(subtitulo) if subtitulo) ].compact) } ]
      if vivo
        atualizacao = { id: "indicadores-da-pagina", "hx-get": vivo.fetch(:url), "hx-trigger": vivo.fetch(:eventos).map { |evento| "#{evento} from:body delay:250ms" }.join(", "),
                        "hx-select": "#indicadores-da-pagina", "hx-target": "this", "hx-swap": "outerHTML", "hx-push-url": "false" }
        partes << tag.div(safe_join(indicadores), class: "indicadores", **atualizacao)
      elsif indicadores.any?
        partes << tag.div(safe_join(indicadores), class: "indicadores")
      end
      partes << tag.div(capture(&acoes), class: "acoes") if acoes
      safe_join(partes)
    end
  end

  # Botão (i) com a definição de um indicador num popover do HTML (atributo `popover`, sem JavaScript); o popover se ancora no botão.
  def informacao(rotulo, texto, id = nil)
    id ||= "definicao-#{rotulo.parameterize}"
    safe_join([ tag.button("i", type: "button", class: "informacao", popovertarget: id, "aria-label": "Definição de #{rotulo}"),
                tag.div(tag.p(texto), id: id, popover: "auto", class: "definicao") ])
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
      rotulo = safe_join([ titulo, (informacao(titulo, ajuda, "def-#{id}") if ajuda) ].compact, " ")
      safe_join([ tag.span(rotulo, id: "#{id}-titulo", class: "titulo"), tag.div(capture(&opcoes), class: "opcoes") ])
    end
  end

  # Menu de linha (⋯): botão e popover com as ações da linha (links e botões de abrir o painel, ou botões de ação direta).
  def menu_de_linha(id, rotulo, &itens)
    safe_join([ tag.button("⋯", type: "button", class: "menu-de-linha", popovertarget: id, "aria-label": rotulo, data: { acao_de_linha: true }),
                tag.div(capture(&itens), id: id, popover: "auto", class: "menu") ])
  end

  # Abas da ficha: cada aba é um endereço; `itens` são [rótulo, caminho, contagem (ou nil), atual?].
  def abas_da_pagina(rotulo, itens)
    tag.nav(class: "abas", "aria-label": rotulo) do
      safe_join(itens.map do |texto, caminho, contagem, atual|
        link_to(safe_join([ texto, (tag.span(contagem, class: "selo") unless contagem.nil?) ].compact, " "), caminho, aria: { current: (atual ? "page" : nil) })
      end)
    end
  end
end
