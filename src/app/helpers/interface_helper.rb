# Marcação semântica do catálogo do design system (o documento do design system do projeto, seção 6 e revisão 2): ícone, situação e aviso.
module InterfaceHelper
  # Heroicons (outline 24, licença MIT) em SVG embutido: o conjunto fica na árvore, sem CDN e sem JavaScript.
  ICONES = {
    "x-mark" => "M6 18 18 6M6 6l12 12",
    "chevron-down" => "m19.5 8.25-7.5 7.5-7.5-7.5",
    "chevron-up" => "m4.5 15.75 7.5-7.5 7.5 7.5",
    "check-circle" => "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "exclamation-circle" => "M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z",
    "exclamation-triangle" => "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z",
    "information-circle" => "m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z",
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
end
