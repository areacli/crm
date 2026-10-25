# Planilhas de carteira para os testes: gravam um CSV em arquivo temporário e devolvem o caminho.
module CsvHelper
  HEADER = %w[documento nome telefone email contrato titulo vencimento valor descricao papel].freeze

  # Linha pronta de uma planilha válida; `overrides` troca colunas pelo nome.
  def csv_line(overrides = {})
    base = { "documento" => "529.982.247-25", "nome" => "Maria da Silva", "telefone" => "(11) 98765-4321", "email" => "maria@exemplo.com.br",
             "contrato" => "CT-1", "titulo" => "NF-1", "vencimento" => "10/09/2026", "valor" => "1.234,56", "descricao" => "Mensalidade", "papel" => "" }
    base.merge(overrides.transform_keys(&:to_s))
  end

  def write_csv(lines, header: HEADER, encoding: "UTF-8", separator: ";")
    file = Tempfile.new([ "carteira", ".csv" ])
    file.binmode
    body = ([ header.join(separator) ] + lines.map { |line| line.is_a?(Hash) ? header.map { |h| line[h] }.join(separator) : line }).join("\n") + "\n"
    file.write(body.encode(encoding))
    file.close
    (@temporary_csvs ||= []) << file
    file.path
  end
end
