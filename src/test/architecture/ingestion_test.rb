require "test_helper"

# Ingestão (decisão 0031): o formato de quem entrega fica no leitor e nos decodificadores. Depois deles, a validação, a conferência e a confirmação
# trabalham com o registro canônico, e um canal novo não precisa fingir ser planilha.
class IngestionArchitectureTest < ActiveSupport::TestCase
  ROOT = Rails.root
  FORMAT = /\bCSV\b|BrDate\.parse|Money\.parse_cents/

  def code(file) = File.readlines(file).map { |line| line.sub(/#.*/, "") }.join

  test "validadores, conferidores e confirmadores não conhecem o formato do arquivo" do
    names = %w[portfolio/row_validator portfolio/import_checker portfolio/import_confirmer portfolio/confirm_batch portfolio/staging
               payments/payment_row_validator payments/reversal_row_validator payments/import_checker payments/import_confirmer payments/processor
               payments/reversal_processor payments/staging payments/external_payment]
    offenders = names.select { |name| code(ROOT.join("app/models/#{name}.rb")).match?(FORMAT) }

    assert_empty offenders, "formato fora do leitor e dos decodificadores (decisão 0031)"
  end

  test "nenhum canal monta uma linha de planilha falsa" do
    assert_empty Dir[ROOT.join("app/**/*.rb")].select { |file| code(file).match?(/CsvFile|RawRecord\.new/) && !file.end_with?("ingestion/csv_reader.rb") }
  end
end
