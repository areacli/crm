require "test_helper"

# Teste de arquitetura do design system (o documento do design system do projeto, revisão 2, seção 14): o CSS é semântico e usa só os tokens; as views
# não têm estilo embutido, JavaScript embutido nem classe utilitária. "Completamente semântico" vira regra que o `bin/ci` confere.
class DesignSystemArchitectureTest < ActiveSupport::TestCase
  FOLHAS = Dir[Rails.root.join("app/assets/stylesheets/*.css")].reject { |a| a.end_with?("10-tokens.css") }.freeze
  VIEWS = Dir[Rails.root.join("app/views/**/*.erb")].freeze

  UTILITARIAS = /\b(?:flex|grid|block|inline|hidden|(?:m|mt|mb|ml|mr|mx|my|p|pt|pb|pl|pr|px|py|gap|w|h|min-w|max-w)-\d+|text-(?:xs|sm|base|lg|[2-9]?xl)|
                   (?:bg|text|border|ring|fill|stroke)-(?:white|black|[a-z]+-\d{2,3})|font-(?:bold|semibold|medium|light)|rounded(?:-\w+)?|
                   shadow(?:-\w+)?|items-\w+|justify-\w+|sr-only)\b/x

  test "o CSS só tem cor, tamanho de fonte e espaço pelos tokens" do
    problemas = FOLHAS.flat_map do |arquivo|
      File.readlines(arquivo).each_with_index.filter_map do |linha, i|
        sem_comentario = linha.sub(%r{/\*.*?\*/}, "")
        motivo =
          if sem_comentario.match?(/#[0-9a-fA-F]{3,8}\b/) || sem_comentario.match?(/\b(?:rgb|rgba|hsl|hsla)\(/) then "cor fora dos tokens"
          elsif (tamanho = sem_comentario[/font-size:\s*([^;}]+)/, 1]) && !tamanho.match?(/\Avar\(--texto-|\Ainherit|\A0\.9em/) then "tamanho de fonte fora dos tokens"
          elsif sem_comentario.match?(/(?<![\d.])(?:[5-9]|\d{2,})px\b/) && !sem_comentario.match?(/999px|\d+px\s+solid|border-radius/) then "tamanho em px fora dos tokens"
          end
        "#{File.basename(arquivo)}:#{i + 1}: #{motivo}" if motivo
      end
    end

    assert_empty problemas, "CSS fora dos tokens:\n#{problemas.join("\n")}"
  end

  test "o CSS não define classe utilitária" do
    problemas = FOLHAS.flat_map do |arquivo|
      File.read(arquivo).scan(/\.([a-z][\w-]*)/).flatten.uniq.select { |nome| nome.match?(UTILITARIAS) && nome != "icone" }.map { |nome| "#{File.basename(arquivo)}: .#{nome}" }
    end

    assert_empty problemas, "Classes utilitárias no CSS:\n#{problemas.join("\n")}"
  end

  test "as views não têm estilo embutido, JavaScript embutido nem classe utilitária" do
    problemas = VIEWS.flat_map do |arquivo|
      texto = File.read(arquivo)
      achados = []
      achados << "atributo style" if texto.match?(/\sstyle\s*=/)
      achados << "manipulador de evento embutido" if texto.match?(/\son[a-z]+\s*=\s*["']/)
      achados << "script embutido" if texto.match?(/<script(?![^>]*\bsrc=)/)
      texto.scan(/\bclass\s*=\s*["']([^"']+)["']/).flatten.flat_map(&:split).each { |c| achados << "classe utilitária .#{c}" if c.match?(UTILITARIAS) }
      achados.uniq.map { |a| "#{arquivo.delete_prefix("#{Rails.root}/")}: #{a}" }
    end

    assert_empty problemas, "Views fora das regras:\n#{problemas.join("\n")}"
  end

  test "o texto de tela está em pt-BR no HTML e o título tem o nome do sistema" do
    layout = File.read(Rails.root.join("app/views/layouts/application.html.erb"))

    assert_includes layout, 'lang="pt-BR"'
    assert_includes layout, "CRM AreaCli"
  end
end
