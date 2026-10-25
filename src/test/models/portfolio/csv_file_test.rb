require "test_helper"

class Portfolio::CsvFileTest < ActiveSupport::TestCase
  test "lê as colunas em qualquer ordem, sem diferenciar maiúsculas nem acentos, e lista as colunas a mais" do
    path = write_csv([ "Maria;529.982.247-25;NF-1;10/09/2026;1.234,56;x" ], header: %w[NOME Documento TÍTULO Vencimento valor Observação])
    file = Portfolio::CsvFile.new(path)
    rows = file.each_row.to_a

    assert_equal 1, rows.size
    assert_equal "Maria", rows.first.values["nome"]
    assert_equal "NF-1", rows.first.values["titulo"]
    assert_equal [ "Observação" ], file.ignored_columns
    assert_equal 2, rows.first.line
  end

  test "linhas em branco são ignoradas e contadas; células vazias a mais não contam" do
    path = write_csv([ csv_line, "", csv_line("titulo" => "NF-2").then { |l| Portfolio::CsvFile::REQUIRED && l.values.join(";") + ";;" } ])
    file = Portfolio::CsvFile.new(path)
    rows = file.each_row.to_a

    assert_equal 2, rows.size
    assert_equal 1, file.blank_lines
    assert_not rows.last.extra
  end

  test "célula preenchida além do cabeçalho marca a linha como extra; linha curta, como incompleta" do
    path = write_csv([ csv_line.values.join(";") + ";sobrou", "529.982.247-25;Maria" ])
    rows = Portfolio::CsvFile.new(path).each_row.to_a

    assert rows.first.extra
    assert rows.last.short
  end

  test "Windows-1252 é convertido para UTF-8" do
    path = write_csv([ csv_line("nome" => "José Conceição") ], encoding: "Windows-1252")

    assert_equal "José Conceição", Portfolio::CsvFile.new(path).each_row.first.values["nome"]
  end

  test "recusa coluna obrigatória ausente, separador errado, binário e arquivo sem dados" do
    error = assert_raises(Portfolio::ImportRefused) { Portfolio::CsvFile.new(write_csv([ "1;2" ], header: %w[documento nome])) }
    assert_match(/coluna obrigatória ausente: titulo, vencimento, valor/, error.message)

    error = assert_raises(Portfolio::ImportRefused) { Portfolio::CsvFile.new(write_csv([ "a,b" ], header: %w[documento nome], separator: ",")) }
    assert_match(/separador errado/, error.message)

    binario = Tempfile.new("binario")
    binario.binmode
    binario.write("documento;nome\0\0")
    binario.close
    assert_raises(Portfolio::ImportRefused) { Portfolio::CsvFile.new(binario.path) }

    vazio = Portfolio::CsvFile.new(write_csv([]))
    error = assert_raises(Portfolio::ImportRefused) { vazio.each_row.to_a }
    assert_match(/sem linhas de dados/, error.message)
  end
end
