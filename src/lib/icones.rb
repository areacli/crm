# Ícones do CRM (design system, revisão 25; decisão 0035): um conjunto só, o Lucide, em toda a aplicação.
#
# Os originais ficam sem alteração em `vendor/assets/icones/lucide` (só os usados, copiados do pacote `lucide-static`, com a licença ISC ao lado).
# Daqui saem os três usos:
# - o helper `icone` escreve o SVG na página, na cor do texto (`currentColor`);
# - o menu lateral usa o arquivo original como máscara (`casca.css`, classes `icone-menu-*`);
# - os ícones do tema do EasyUI (botões das janelas, paginação, abas, árvore, grade, mensagens, calendário, busca) são arquivos gerados em
#   `vendor/assets/easyui/tema/images`, com a cor do tema gravada no traço, porque o tema os usa como imagem de fundo. `bin/rails crm:icones:tema`
#   refaz esses arquivos, e um teste de arquitetura confere que estão iguais ao que o mapa abaixo gera.
module Icones
  VERSAO = "1.65.0".freeze
  # Integridade do pacote no npm (`lucide-static-1.65.0.tgz`, publicado em 30/10/2026), conferida no download.
  INTEGRIDADE = "sha512-Mbahsp1MHXzBK2qQ+j+OpdwvPwOFYFBOe2pD1O5eI+XLRpbqPY2euz6vemAddXGevRvJ5n8D83ilUCrtxP07RQ==".freeze
  ORIGINAIS = Rails.root.join("vendor/assets/icones/lucide")
  TEMA = Rails.root.join("vendor/assets/easyui/tema/images")

  # As cores do tema (as da marca): o traço do ícone de fundo não herda a cor do texto.
  CORES = { marinho: "#1c3a57", azul: "#2a6496", vermelho: "#b3261e", laranja: "#b4531a", verde: "#1f7a4d" }.freeze

  # Arquivo do tema => [ícone do Lucide, cor]. A regra do `easyui.css` que usa cada um está no comentário.
  DO_TEMA = {
    "fechar.svg" => [ "x", :marinho ],                          # .panel-tool-close, .tabs li .tabs-close, .tagbox-remove
    "minimizar.svg" => [ "minus", :marinho ],                   # .panel-tool-min
    "maximizar.svg" => [ "maximize-2", :marinho ],              # .panel-tool-max
    "restaurar.svg" => [ "minimize-2", :marinho ],              # .panel-tool-restore
    "seta-acima.svg" => [ "chevron-up", :marinho ],             # .panel-tool-collapse, .accordion-collapse, .sidemenu (grupo aberto), .spinner-arrow-up
    "seta-abaixo.svg" => [ "chevron-down", :marinho ],          # .panel-tool-expand, .accordion-expand, .sidemenu (grupo fechado), .combo-arrow, .m-btn-downarrow, .tree-expanded, .datagrid-row-collapse
    "seta-esquerda.svg" => [ "chevron-left", :marinho ],        # .tabs-scroller-left, .pagination-prev, .calendar-prevmonth, .calendar-menu-prev
    "seta-direita.svg" => [ "chevron-right", :marinho ],        # .tabs-scroller-right, .pagination-next, .calendar-nextmonth, .calendar-menu-next, .menu-rightarrow, .tree-collapsed, .datagrid-row-expand
    "setas-acima.svg" => [ "chevrons-up", :marinho ],           # .layout-button-up
    "setas-abaixo.svg" => [ "chevrons-down", :marinho ],        # .layout-button-down
    "setas-esquerda.svg" => [ "chevrons-left", :marinho ],      # .layout-button-left, .calendar-prevyear
    "setas-direita.svg" => [ "chevrons-right", :marinho ],      # .layout-button-right, .calendar-nextyear
    "primeira.svg" => [ "chevron-first", :marinho ],            # .pagination-first
    "ultima.svg" => [ "chevron-last", :marinho ],               # .pagination-last
    "recarregar.svg" => [ "rotate-cw", :marinho ],              # .pagination-load
    "carregando.svg" => [ "loader-circle", :azul ],             # .panel-loading, .datagrid-mask-msg, .pagination-loading, .tree-loading (gira)
    "ordem.svg" => [ "arrow-up-down", :marinho ],               # .datagrid-sort .datagrid-sort-icon
    "ordem-crescente.svg" => [ "arrow-up", :marinho ],          # .datagrid-sort-asc .datagrid-sort-icon
    "ordem-decrescente.svg" => [ "arrow-down", :marinho ],      # .datagrid-sort-desc .datagrid-sort-icon
    "calendario.svg" => [ "calendar", :marinho ],               # .datebox .combo-arrow
    "buscar.svg" => [ "search", :marinho ],                     # .searchbox-button
    "mostrar-senha.svg" => [ "eye", :marinho ],                 # .passwordbox-open
    "esconder-senha.svg" => [ "eye-off", :marinho ],            # .passwordbox-close
    "mensagem-informacao.svg" => [ "info", :azul ],             # .messager-info
    "mensagem-pergunta.svg" => [ "circle-question-mark", :azul ], # .messager-question
    "mensagem-erro.svg" => [ "circle-x", :vermelho ],           # .messager-error
    "mensagem-atencao.svg" => [ "triangle-alert", :laranja ],   # .messager-warning
    "pasta.svg" => [ "folder", :marinho ],                      # .tree-folder
    "pasta-aberta.svg" => [ "folder-open", :marinho ],          # .tree-folder-open
    "arquivo.svg" => [ "file", :marinho ],                      # .tree-file
    "marcar.svg" => [ "square", :marinho ],                     # .tree-checkbox0
    "marcado.svg" => [ "square-check", :azul ],                 # .tree-checkbox1
    "marcado-em-parte.svg" => [ "square-minus", :azul ],        # .tree-checkbox2
    "abrir-ramo.svg" => [ "square-plus", :marinho ],            # .tree-lines .tree-collapsed
    "fechar-ramo.svg" => [ "square-minus", :marinho ],          # .tree-lines .tree-expanded
    "pode-soltar.svg" => [ "check", :verde ],                   # .tree-dnd-yes
    "nao-pode-soltar.svg" => [ "x", :vermelho ]                 # .tree-dnd-no
  }.freeze

  # As linhas da árvore (opção `lines`, que o CRM não usa) não são ícones: o tema as desenha com o mesmo traço, pontilhado e na cor da borda.
  LINHAS = {
    "linha-da-arvore.svg" => '<path d="M9 0v18" />',              # .tree-line
    "juncao-da-arvore.svg" => '<path d="M9 0v18M9 9h9" />',       # .tree-join
    "fim-da-arvore.svg" => '<path d="M9 0v9h9" />'                # .tree-joinbottom
  }.freeze

  class << self
    def nomes = conteudos.keys

    # O desenho do ícone (os elementos de dentro do `<svg>` original), para o helper e para o tema.
    def conteudo(nome)
      conteudos.fetch(nome.to_s) { raise ArgumentError, "ícone desconhecido: #{nome} (os do Lucide ficam em vendor/assets/icones/lucide)" }
    end

    # O arquivo do tema: o desenho original com a cor gravada no traço. O "carregando" gira pela própria animação do SVG, que vale em imagem de fundo.
    def svg_do_tema(arquivo)
      nome, cor = DO_TEMA.fetch(arquivo)
      giro = nome == "loader-circle" ? '<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.8s" repeatCount="indefinite" />' : ""
      svg(%(<g>#{conteudo(nome)}#{giro}</g>), CORES.fetch(cor), "Lucide #{VERSAO}, #{nome}, licença ISC")
    end

    def linha_do_tema(arquivo)
      svg(LINHAS.fetch(arquivo), "#c9d4de", "linha da árvore do tema", viewbox: "0 0 18 18", traco: %( stroke-width="1" stroke-dasharray="1 1"))
    end

    # Todos os arquivos do tema, como devem estar no disco.
    def arquivos_do_tema
      DO_TEMA.keys.index_with { svg_do_tema(_1) }.merge(LINHAS.keys.index_with { linha_do_tema(_1) })
    end

    def gravar_tema!
      arquivos_do_tema.each { |arquivo, svg| File.write(TEMA.join(arquivo), svg) }
    end

    private
      def conteudos
        @conteudos ||= Dir[ORIGINAIS.join("*.svg")].sort.to_h do |arquivo|
          desenho = File.read(arquivo)[%r{<svg[^>]*>(.*)</svg>}m, 1].to_s.lines.map(&:strip).reject(&:empty?).join
          [ File.basename(arquivo, ".svg"), desenho.freeze ]
        end.freeze
      end

      def svg(desenho, cor, origem, viewbox: "0 0 24 24", traco: %( stroke-width="2" stroke-linecap="round" stroke-linejoin="round"))
        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="#{viewbox}" fill="none" stroke="#{cor}"#{traco}><!-- #{origem} -->#{desenho}</svg>
        SVG
      end
  end
end
