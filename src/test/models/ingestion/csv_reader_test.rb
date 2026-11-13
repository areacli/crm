require "test_helper"

class Ingestion::CsvReaderTest < ActiveSupport::TestCase
  def reader(path) = Ingestion::CsvReader.new(path, required: Portfolio::Layout::REQUIRED, optional: Portfolio::Layout::OPTIONAL)

  test "lê as colunas em qualquer ordem, sem diferenciar maiúsculas nem acentos, e lista as colunas a mais" do
    path = write_csv([ "Maria;529.982.247-25;NF-1;10/09/2026;1.234,56;x" ], header: %w[NOME Documento TÍTULO Vencimento valor Observação])
    file = reader(path)
    rows = file.each_record.to_a

    assert_equal 1, rows.size
    assert_equal "Maria", rows.first.values["nome"]
    assert_equal "NF-1", rows.first.values["titulo"]
    assert_equal [ "Observação" ], file.ignored_columns
    assert_equal 2, rows.first.position
  end

  test "linhas em branco são ignoradas e contadas; células vazias a mais não contam" do
    path = write_csv([ csv_line, "", csv_line("titulo" => "NF-2").values.join(";") + ";;" ])
    file = reader(path)
    rows = file.each_record.to_a

    assert_equal 2, rows.size
    assert_equal 1, file.blank_lines
    assert_not rows.last.extra
  end

  test "célula preenchida além do cabeçalho marca a linha como extra; linha curta, como incompleta" do
    path = write_csv([ csv_line.values.join(";") + ";sobrou", "529.982.247-25;Maria" ])
    rows = reader(path).each_record.to_a

    assert rows.first.extra
    assert rows.last.short
  end

  test "a célula de uma coluna ignorada não é célula a mais, esteja a coluna no meio ou no fim do cabeçalho" do
    header = %w[documento nome observação titulo vencimento valor anotação]
    path = write_csv([ "529.982.247-25;Maria;obs;NF-1;10/09/2026;100,00;nota", "529.982.247-25;Maria;obs;NF-2;10/09/2026;100,00;nota;sobrou",
                       "529.982.247-25;Maria;obs;NF-3;10/09/2026;100,00", "529.982.247-25;Maria;obs;NF-4;10/09/2026" ], header: header)
    file = reader(path)
    rows = file.each_record.to_a

    assert_equal %w[observação anotação], file.ignored_columns
    assert_equal %w[NF-1 NF-2 NF-3 NF-4], rows.map { |row| row.values["titulo"] }
    assert_equal "100,00", rows.first.values["valor"]
    assert_equal [ false, true, false, false ], rows.map(&:extra)
    # Só é curta a linha que não chega à última coluna conhecida: a que deixa de fora só a coluna ignorada do fim está completa.
    assert_equal [ false, false, false, true ], rows.map(&:short)
  end

  test "Windows-1252 é convertido para UTF-8" do
    path = write_csv([ csv_line("nome" => "José Conceição") ], encoding: "Windows-1252")

    assert_equal "José Conceição", reader(path).each_record.first.values["nome"]
  end

  test "recusa coluna obrigatória ausente, separador errado, binário e arquivo sem dados" do
    error = assert_raises(Portfolio::ImportRefused) { reader(write_csv([ "1;2" ], header: %w[documento nome])) }
    assert_match(/coluna obrigatória ausente: titulo, vencimento, valor/, error.message)

    error = assert_raises(Portfolio::ImportRefused) { reader(write_csv([ "a,b" ], header: %w[documento nome], separator: ",")) }
    assert_match(/separador errado/, error.message)

    binario = Tempfile.new("binario")
    binario.binmode
    binario.write("documento;nome\0\0")
    binario.close
    assert_raises(Portfolio::ImportRefused) { reader(binario.path) }

    vazio = reader(write_csv([]))
    error = assert_raises(Portfolio::ImportRefused) { vazio.each_record.to_a }
    assert_match(/sem linhas de dados/, error.message)
  end
end
