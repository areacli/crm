# Envio de arquivo na SPA (R10, R44, R56; decisão 0025): os credores em que a pessoa pode enviar o tipo e as colunas da planilha.
colunas = if @kind == "portfolio"
  Portfolio::SheetModel::COLUMNS.map { |column| [ column, Portfolio::SheetModel.required?(column), Portfolio::SheetModel.format_text(column), Portfolio::SheetModel.example(column) ] }
else
  Payments::SheetModel.columns(@kind).map { |column| [ column, Payments::SheetModel.required?(@kind, column), Payments::SheetModel.format_text(@kind, column), Payments::SheetModel.example(@kind, column) ] }
end
json.tipo @kind
json.titulo({ "portfolio" => "Importar carteira", "payments" => "Importar pagamentos", "reversals" => "Importar estornos" }.fetch(@kind))
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.com_modo @kind == "portfolio"
json.modelo template_imports_path(kind: @kind)
json.demonstracao Demo.enabled?
json.obrigatorias colunas.select { |_, obrigatoria, _, _| obrigatoria }.map(&:first).to_sentence(two_words_connector: " e ", last_word_connector: " e ")
json.ajuda_das_colunas("Separador ponto e vírgula, UTF-8 ou Windows-1252. A ordem das colunas é livre; o cabeçalho é obrigatório.#{" A planilha modelo, sem alteração, é aceita na conferência." if @kind == "portfolio"}")
json.colunas(colunas.map { |nome, obrigatoria, formato, exemplo| { nome: nome, obrigatoria: obrigatoria ? "Sim" : "Não", formato: formato, exemplo: exemplo } })
