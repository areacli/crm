# A aplicação OpenUI5 do CRM (decisão 0025): os módulos ficam em app/ui5/crm e são servidos por Ui5AppController num caminho com a versão
# do conteúdo (`/crm/<versão>/…`), com cache longo. Mudou um arquivo, muda a versão, e o navegador busca de novo.
module Ui5App
  RAIZ = Rails.root.join("app/ui5/crm").freeze
  TIPOS = { ".js" => "text/javascript", ".json" => "application/json", ".xml" => "application/xml", ".properties" => "text/plain",
            ".css" => "text/css", ".svg" => "image/svg+xml" }.freeze

  module_function

  # A versão do OpenUI5 (bin/ui5-instalar instala a mesma, e o teste confere).
  def openui5 = Rails.root.join("config/ui5_versao").read.strip

  # Resumo do conteúdo da aplicação: calculado uma vez em produção; em desenvolvimento e teste, a cada pedido (arquivos mudam).
  def versao
    return @versao if @versao && Rails.env.production?

    @versao = Digest::SHA256.hexdigest(arquivos.sort.map { |caminho| [ caminho, File.mtime(caminho).to_i, File.size(caminho) ].join(":") }.join("|"))[0, 12]
  end

  def arquivos = Dir.glob(RAIZ.join("**/*")).select { |caminho| File.file?(caminho) }

  # O pacote de pré-carga no formato do OpenUI5 (`sap.ui.require.preload`): todos os módulos num pedido só. O código vai como função (sem
  # `eval`, compatível com a CSP); views, fragmentos, textos e o manifest vão como texto. Gerado em memória, por versão.
  def preload
    return @preload[1] if @preload && @preload[0] == versao

    modulos = arquivos.sort.filter_map do |caminho|
      nome = "crm/#{Pathname(caminho).relative_path_from(RAIZ)}"
      case File.extname(caminho)
      when ".js" then "#{nome.to_json}:function(){\n#{File.read(caminho)}\n}"
      when ".xml", ".json", ".properties" then "#{nome.to_json}:#{File.read(caminho).to_json}"
      end
    end
    @preload = [ versao, "//@ui5-bundle crm/Component-preload.js\nsap.ui.require.preload({\n#{modulos.join(",\n")}\n});\n" ]
    @preload[1]
  end

  # O arquivo pedido, só se estiver dentro da raiz e tiver um tipo conhecido (nada de `..`).
  def arquivo(caminho)
    completo = RAIZ.join(caminho).expand_path
    completo if completo.to_s.start_with?("#{RAIZ}/") && TIPOS.key?(completo.extname) && completo.file?
  end
end
