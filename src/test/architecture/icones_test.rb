require "test_helper"

# Um conjunto de ícones só, o Lucide (design system, revisão 25; decisão 0035): no helper, no menu lateral e no tema do EasyUI.
class IconesTest < ActiveSupport::TestCase
  TEMA = Icones::TEMA
  # O que fica na pasta de imagens do tema e não é ícone: o gif transparente, a alça do controle deslizante e o fundo do botão.
  NAO_ICONES = %w[blank.gif slider_handle.png linkbutton_bg.png].freeze
  FONTES = Dir[Rails.root.join("app/{views,helpers,javascript}/**/*.{erb,rb,js}")].freeze

  test "os originais do Lucide estão sem alteração e com a licença ao lado" do
    Dir[Icones::ORIGINAIS.join("*.svg")].each do |arquivo|
      assert File.read(arquivo).start_with?("<!-- @license lucide-static v#{Icones::VERSAO} - ISC -->"), File.basename(arquivo)
    end
    assert_match "ISC License", File.read(Icones::ORIGINAIS.join("../LICENSE"))
  end

  test "os ícones do tema são os que o mapa gera, e o tema não guarda outros" do
    Icones.arquivos_do_tema.each { |arquivo, svg| assert_equal svg, File.read(TEMA.join(arquivo)), "#{arquivo}: rode bin/rails crm:icones:tema" }
    sobras = Dir.children(TEMA) - Icones.arquivos_do_tema.keys - NAO_ICONES

    assert_empty sobras, "imagem no tema fora do Lucide"
  end

  test "o tema só aponta para imagens que existem, e nenhuma é sprite" do
    css = Dir[Rails.root.join("vendor/assets/easyui/tema/*.css")].sum("") { File.read(_1) }
    imagens = css.scan(%r{url\('images/([^']+)'\)}).flatten.uniq

    assert_empty imagens.reject { TEMA.join(_1).exist? }
    assert_empty imagens.grep(/\.(png|gif)\z/) - NAO_ICONES
    refute Rails.root.join("vendor/assets/easyui/tema/icon.css").exist?, "as classes icon-* de exemplo do EasyUI saíram"
  end

  test "todo ícone pedido existe, e todo original guardado é usado" do
    pedidos = FONTES.flat_map { File.read(_1).scan(/\bicone\("([a-z0-9-]+)"/).flatten }
    textos = FONTES.sum("") { File.read(_1) } + File.read(Rails.root.join("lib/assets/casca/casca.css"))
    usados = Icones.nomes.select { |nome| textos.include?(%("#{nome}")) || textos.include?("lucide/#{nome}.svg") } + Icones::DO_TEMA.values.map(&:first)

    assert_empty pedidos.uniq - Icones.nomes, "ícone que não está em vendor/assets/icones/lucide"
    assert_empty Icones.nomes - usados, "original do Lucide guardado sem uso"
  end

  test "nenhuma tela usa glifo no lugar de ícone" do
    # O "›" entre nomes de tela ("Configuração › Operações") é texto, não ícone; os comentários podem citar o glifo antigo.
    glifos = /[⋯⋮≡▾▴▸◂▶◀▼▲✕✖✓✔]/
    achados = FONTES.flat_map do |arquivo|
      File.read(arquivo).gsub(/<%#.*?%>/m) { _1.gsub(/[^\n]/, "") }.lines.each_with_index.filter_map do |linha, indice|
        codigo = linha.chomp.sub(%r{\s*(#|//).*\z}, "")
        "#{arquivo.delete_prefix(Rails.root.to_s)}:#{indice + 1}" if codigo.match?(glifos)
      end
    end

    assert_empty achados
  end
end
