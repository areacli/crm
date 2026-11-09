# A planilha de cada tipo de importação (R44, R47): as colunas que a tela mostra e o modelo que se baixa saem do mesmo conjunto.
module ImportSheet
  NAMES = { "portfolio" => "modelo-carteira.csv", "payments" => "modelo-pagamentos.csv", "reversals" => "modelo-estornos.csv" }.freeze

  module_function

  def template(kind) = kind == "portfolio" ? Portfolio::SheetModel.csv : Payments::SheetModel.csv(kind)

  def template_name(kind) = NAMES.fetch(kind)

  # Nome, se é obrigatória, formato e exemplo de cada coluna.
  def columns(kind)
    return Portfolio::SheetModel::COLUMNS.map { |name| [ name, Portfolio::SheetModel.required?(name), Portfolio::SheetModel.format_text(name), Portfolio::SheetModel.example(name) ] } if kind == "portfolio"

    Payments::SheetModel.columns(kind).map { |name| [ name, Payments::SheetModel.required?(kind, name), Payments::SheetModel.format_text(kind, name), Payments::SheetModel.example(kind, name) ] }
  end
end
