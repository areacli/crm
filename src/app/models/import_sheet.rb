# A planilha de cada tipo de importação (R44, R47): as colunas que a tela mostra e o modelo que se baixa saem do mesmo conjunto.
module ImportSheet
  NAMES = { "portfolio" => "modelo-carteira.csv", "payments" => "modelo-pagamentos.csv", "reversals" => "modelo-estornos.csv" }.freeze

  module_function

  # `ids`: com as colunas de id remoto da carteira (17, R401), para quem tem credor com sistema remoto. `remote`: os sistemas remotos desses credores, de
  # onde saem as colunas `sistema` e `id_titulo` dos pagamentos e dos estornos (R416, R417).
  def template(kind, ids: false, remote: []) = kind == "portfolio" ? Portfolio::SheetModel.csv(ids: ids) : Payments::SheetModel.csv(kind, remote: remote)

  def template_name(kind) = NAMES.fetch(kind)

  # Nome, se é obrigatória, formato e exemplo de cada coluna.
  def columns(kind, ids: false, remote: [])
    return Portfolio::SheetModel.columns(ids: ids).map { |name| [ name, Portfolio::SheetModel.required?(name), Portfolio::SheetModel.format_text(name), Portfolio::SheetModel.example(name) ] } if kind == "portfolio"

    sheet = Payments::SheetModel
    sheet.columns(kind, remote: remote).map { |name| [ name, sheet.required?(kind, name, remote: remote), sheet.format_text(kind, name, remote: remote), sheet.example(kind, name, remote: remote) ] }
  end
end
