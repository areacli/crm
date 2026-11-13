require "test_helper"
require "digest"

# Teste de arquitetura da SPA em EasyUI (decisão 0028): o EasyUI fica nos helpers e nos módulos `spa/`, para a próxima troca de interface não tocar nas telas; os arquivos dele não mudam
# (a licença gratuita não dá direito de modificar); e todo pedido passa pelo jQuery, onde a espera pelo servidor é tratada.
class SpaArchitectureTest < ActiveSupport::TestCase
  VIEWS = Dir[Rails.root.join("app/views/**/*.erb")].freeze
  MODULOS = Dir[Rails.root.join("app/javascript/spa/*.js")].freeze
  EASYUI = Rails.root.join("vendor/assets/easyui")

  test "nenhuma view escreve classe do EasyUI, data-options ou chama plugin" do
    problemas = VIEWS.select { |arquivo| File.read(arquivo).match?(/easyui-(?!lang)|data-options/) }.map { |arquivo| arquivo.delete_prefix(Rails.root.to_s) }

    assert_empty problemas, "EasyUI fora dos helpers e dos módulos spa/:\n#{problemas.join("\n")}"
  end

  # A grade da SPA (`spa/grade`) tira as colunas do <thead>: uma tabela sem ele vira um cartão vazio (o de descontos do resumo, achado nas fotos da fase 8).
  # Ficam de fora as páginas que o servidor serve direto (impressão, pagamento, erro), onde a tabela não vira grade.
  test "toda tabela das telas da casca tem cabeçalho" do
    fora = %r{/(layouts|checkouts|errors|agreement_terms|customers/data_exports)/}
    problemas = VIEWS.reject { |arquivo| fora.match?(arquivo) }.select do |arquivo|
      texto = File.read(arquivo)
      texto.scan(/<table\b/).size > texto.scan(/<thead\b/).size
    end
    assert_empty problemas.map { |arquivo| arquivo.delete_prefix(Rails.root.to_s) }, "tabela sem <thead>"
  end

  # As rotas são em português (pedido do Paulo, 08/11/2026): fora ficam só os nomes técnicos que não são tela: /up, /cable, /webhooks e os do próprio Rails.
  test "nenhuma rota tem trecho em inglês" do
    ingles = %r{/(new|edit|session|sessions|show|index|create|update|delete|destroy)(/|\(|\z)}
    rotas = Rails.application.routes.routes.map { |rota| rota.path.spec.to_s }.reject { |caminho| caminho.start_with?("/rails/", "/assets") }
    assert_empty rotas.grep(ingles)
  end

  # Os parâmetros do endereço também (revisão 39): os controladores leem o nome em português, e o valor de filtro passa por `FilterValue`.
  test "nenhum link nem campo de filtro manda parâmetro em inglês" do
    internos = %w[tenant tenant_id q page per_page retained_page status kind from to user origin operation source result operator channel state segment promise bracket address offset subject change member_id contract_id bill_id sort dir]
    fontes = (VIEWS + Dir[Rails.root.join("app/helpers/**/*.rb")] + Dir[Rails.root.join("app/controllers/**/*.rb")])
    links = fontes.flat_map { |arquivo| File.read(arquivo).scan(/_(?:path|url)\([^()\n]*\b(#{internos.join("|")}):\s/).flatten.map { |nome| "#{arquivo.delete_prefix(Rails.root.to_s)}: #{nome}" } }
    assert_empty links, "link com parâmetro em inglês"
    campos = VIEWS.flat_map { |arquivo| File.read(arquivo).scan(/\bname="(#{internos.join("|")})"/).flatten.map { |nome| "#{arquivo.delete_prefix(Rails.root.to_s)}: #{nome}" } }
    assert_empty campos, "campo com parâmetro em inglês"
    leituras = (Dir[Rails.root.join("app/controllers/**/*.rb")] + VIEWS - [ Rails.root.join("app/controllers/errors_controller.rb").to_s, Rails.root.join("app/views/customer_contacts/statuses/edit.html.erb").to_s ])
               .flat_map { |arquivo| File.read(arquivo).scan(/\bparams\[:(#{internos.join("|")})\](?!\[)/).flatten.map { |nome| "#{arquivo.delete_prefix(Rails.root.to_s)}: #{nome}" } }
    assert_empty leituras, "leitura de parâmetro em inglês"
    assert_equal FilterValue::VALUES.size, FilterValue::VALUES.values.uniq.size, "dois valores internos com o mesmo nome na URL"
  end

  test "os módulos da SPA não usam data-options nem fazem pedido fora do jQuery" do
    problemas = MODULOS.select { |arquivo| File.read(arquivo).match?(/data-options|\bfetch\(|XMLHttpRequest/) }.map { |arquivo| File.basename(arquivo) }

    assert_empty problemas, "Pedido fora do caminho da espera:\n#{problemas.join("\n")}"
  end

  test "a camada nossa não escreve sobre classe interna do EasyUI" do
    internas = /\.(?:datagrid|tabs|panel|window|dialog|combo|textbox|tree|sidemenu|messager|l-btn|layout|pagination|accordion)(?:-[\w-]+)?(?![\w-])/
    css = File.read(Rails.root.join("lib/assets/casca/casca.css")).gsub(%r{/\*.*?\*/}m, "")

    assert_empty css.scan(internas).uniq
  end

  test "os arquivos do EasyUI continuam sem alteração" do
    esperados = {
      "jquery.min.js" => "39a546ea9ad97f8bfaf5d3e0e8f8556adb415e470e59007ada9759dce472adaa",
      "jquery.easyui.min.js" => "a18a0b3e4cf3d87ec584e76245bcee97f141241cf38b56489be337700d502093",
      "easyui-lang-pt_BR.js" => "2ce16ad375d4f95c15cb56ac06262ecc5f636f2152ed409d6843304b0c97871e",
      # Extensão `datagrid-detailview` (pacote `jquery-easyui-datagridview` 1.0.6): o arquivo não traz licença, e o Paulo decidiu tratá-la como parte do EasyUI gratuito (07/11/2026).
      "datagrid-detailview.js" => "b580ea73c9b967e34ba6e42c53f066f2f903f2256bd5f5338c3a59a7f66fccda"
    }

    esperados.each { |arquivo, sha| assert_equal sha, Digest::SHA256.file(EASYUI.join(arquivo)).hexdigest, arquivo }
    assert EASYUI.join("license_freeware.txt").exist?, "a licença do EasyUI acompanha os arquivos"
  end
end
