require "test_helper"

# O estado do título só muda pelo modelo (plano técnico da camada 23, decisão 2, "Ponto único no modelo"): o registro pelo callback que grava as
# datas de cobrança, o conjunto por `Bill#change_status_to!`. Um `update_all` ou `update_columns` de estado de título em outro lugar passaria sem
# as datas, e o episódio de atraso da régua (21, R434) sairia errado sem nenhum erro aparente.
class BillStatusArchitectureTest < ActiveSupport::TestCase
  ROOT = Rails.root
  # Linha que escreve o estado sem callback, sobre título: `Bill...`, `bills`, `titles`, `reversal_titles` ou uma variável `bill`.
  BULK_STATUS = /\b(update_all|update_columns?|upsert_all)\b[^#\n]*\bstatus\b/
  BILLISH = /\b(Bill\b|bills?\b|titles\b|reversal_titles\b|entry_title\b)/

  test "nenhum código muda o estado de título por update_all, update_columns ou upsert_all fora do modelo" do
    files = Dir[ROOT.join("{app,lib}/**/*.{rb,rake}")] - [ ROOT.join("app/models/bill.rb").to_s ]
    offenders = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        code = line.sub(/#.*/, "")
        "#{file.delete_prefix("#{ROOT}/")}:#{index + 1}" if code.match?(BULK_STATUS) && code.match?(BILLISH)
      end
    end
    assert_empty offenders, "use Bill#change_status_to! (conjunto) ou update!/save (registro), que gravam closed_on e reopened_on"
  end

  test "o modelo grava as datas de cobrança antes de salvar e tem o caminho do conjunto" do
    assert Bill._save_callbacks.any? { |callback| callback.kind == :before && callback.filter == :track_collection_dates }
    assert_respond_to Bill.all, :change_status_to!
  end
end
