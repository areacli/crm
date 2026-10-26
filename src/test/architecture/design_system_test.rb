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

  # Regra de ação da revisão 4 (decisão 0022): nenhuma ação da ficha vive num formulário aberto na página nem num <details>. Formulário de verdade abre no painel
  # compartilhado; o que a ficha tem são botões de ação direta (`button_to`, sem campo) e a edição na própria linha, sob pedido.
  FICHA = Dir[Rails.root.join("app/views/customers/{show,_contracts,_segment_history}.html.erb")] + Dir[Rails.root.join("app/views/customers/{tabs,contacts,promises,agreements}/*.erb")]
  EDICAO_NA_LINHA = [ "customers/contacts/_row_editor.html.erb" ].freeze

  test "a ficha não tem <details> com formulário nem formulário inline com campos" do
    problemas = FICHA.reject { |arquivo| EDICAO_NA_LINHA.any? { |permitido| arquivo.end_with?(permitido) } }.flat_map do |arquivo|
      texto = File.read(arquivo)
      achados = []
      texto.scan(%r{<details\b.*?</details>}m).each { |bloco| achados << "<details> com formulário" if bloco.match?(/<form|form_with|form_tag|button_to|<input|<select|<textarea/) }
      achados << "formulário inline com campos" if texto.match?(/form_with|form_tag|<form\b|<input\b|<select\b|<textarea\b|text_field|text_area|select_tag/)
      achados.uniq.map { |achado| "#{arquivo.delete_prefix("#{Rails.root}/")}: #{achado}" }
    end

    assert_empty problemas, "A ação com dados abre no painel (decisão 0022):\n#{problemas.join("\n")}"
  end

  # A simulação de acordo é fluxo rico, com página própria (formulário e resultado lado a lado), e fica fora.
  test "os formulários de painel vêm do helper formulario_de_painel" do
    problemas = Dir[Rails.root.join("app/views/{customers,customer_contacts,promises}/**/{new,edit}.html.erb")].reject { |arquivo| arquivo.include?("agreement_simulations") || File.read(arquivo).include?("formulario_de_painel") }.map { |arquivo| arquivo.delete_prefix("#{Rails.root}/") }

    assert_empty problemas, "Formulário de painel sem o helper:\n#{problemas.join("\n")}"
  end

  # Fase 2 (decisão 0022): a regra vale para o app inteiro. Nenhuma view tem <details> com formulário, nenhum <dialog> nasce numa view (só o do layout, que o painel
  # preenche) e a confirmação de ação é a do painel (`confirmar_no_painel`).
  APP = VIEWS.reject { |arquivo| arquivo.include?("/design_system/") || arquivo.include?("/layouts/_painel") }
  # O menu do usuário e o sino são menus de cabeçalho (botão de sair, marcar como lido), não formulários de dados.
  MENUS_DO_CABECALHO = %w[layouts/application notices/_bell].freeze

  test "nenhuma view do app tem <details> com formulário" do
    problemas = APP.reject { |arquivo| MENUS_DO_CABECALHO.any? { |menu| arquivo.include?(menu) } }.filter_map do |arquivo|
      texto = File.read(arquivo)
      arquivo.delete_prefix("#{Rails.root}/") if texto.scan(%r{<details\b.*?</details>}m).any? { |bloco| bloco.match?(/<form|form_with|form_tag|button_to|<input|<select|<textarea|_field|_tag/) }
    end

    assert_empty problemas, "<details> com formulário (use o painel):\n#{problemas.join("\n")}"
  end

  test "nenhuma view do app declara um <dialog> próprio" do
    problemas = APP.select { |arquivo| File.read(arquivo).match?(/<dialog\b/) }.map { |arquivo| arquivo.delete_prefix("#{Rails.root}/") }

    assert_empty problemas, "<dialog> de instância (use o painel compartilhado):\n#{problemas.join("\n")}"
  end

  test "a confirmação por instância (shared/confirmacao) não existe mais" do
    refute File.exist?(Rails.root.join("app/views/shared/_confirmacao.html.erb"))
    assert_empty APP.select { |arquivo| File.read(arquivo).include?("shared/confirmacao") }.map { |arquivo| arquivo.delete_prefix("#{Rails.root}/") }
  end

  # Formulário de ação (new/edit de painel) usa o helper; as páginas de edição da configuração e o envio de planilha são páginas de verdade e ficam fora.
  PAGINAS_DE_FORMULARIO = %w[settings/channels/edit settings/segments/ settings/payment_accounts/ imports/new customer_contacts/edit].freeze

  test "todo new/edit de ação do app usa o formulario_de_painel" do
    problemas = APP.select { |arquivo| arquivo.match?(%r{/(new|edit)\.html\.erb\z}) }
                   .reject { |arquivo| PAGINAS_DE_FORMULARIO.any? { |pagina| arquivo.include?(pagina) } || arquivo.include?("agreement_simulations") || arquivo.include?("/passwords/") || arquivo.include?("/sessions/") }
                   .reject { |arquivo| File.read(arquivo).include?("formulario_de_painel") || File.read(arquivo).include?("render \"profiles/form\"") || File.read(arquivo).match?(/render "[a-z_\/]+\/form"/) }
                   .map { |arquivo| arquivo.delete_prefix("#{Rails.root}/") }

    assert_empty problemas, "Formulário de ação sem o helper do painel:\n#{problemas.join("\n")}"
  end

  # Toda ação que pede dados fora de uma tabela editável ou da configuração abre no painel: a lista de telas (index) não tem formulário com campo de dados além dos filtros.
  test "as listas não têm formulário de dados inline (só filtros e botões de ação direta)" do
    listas = APP.select { |arquivo| arquivo.match?(%r{/(index|_result|_list|_page)\.html\.erb\z}) && !arquivo.include?("/settings/") }
    problemas = listas.filter_map do |arquivo|
      texto = File.read(arquivo).gsub(/<form class="filtros".*?<\/form>/m, "")
      arquivo.delete_prefix("#{Rails.root}/") if texto.match?(/form_with|<form\b|text_field|text_area|select_tag|<textarea/)
    end

    assert_empty problemas, "Formulário de dados dentro da lista:\n#{problemas.join("\n")}"
  end
end
