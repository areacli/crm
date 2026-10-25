require "test_helper"

# R44: a planilha-modelo, enviada sem alteração, passa na conferência com 3 títulos válidos e nenhuma recusa.
class Portfolio::SheetModelTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "tem o cabeçalho das colunas e três linhas, em CSV com ponto e vírgula e UTF-8" do
    lines = Portfolio::SheetModel.csv.delete_prefix("﻿").split("\r\n")

    assert_equal "documento;nome;titulo;vencimento;valor;telefone;email;contrato;descricao;papel", lines.first
    assert_equal 4, lines.size
    assert_equal Encoding::UTF_8, Portfolio::SheetModel.csv.encoding
  end

  test "enviada sem alteração, é aceita na conferência: 3 títulos válidos e nenhuma recusa" do
    file = Tempfile.new([ "modelo", ".csv" ])
    file.binmode
    file.write(Portfolio::SheetModel.csv)
    file.close

    import = Portfolio::ImportService.new.start(tenant: tenants(:alfa), user: users(:joana), file: file.path, mode: :incremental, original_name: "modelo-carteira.csv")
    perform_enqueued_jobs(only: CheckImportJob)

    summary = import.reload.summary_data
    assert import.checked?
    assert_equal [ 3, 0, 3 ], [ summary[:valid], summary[:rejected], summary[:customers] ]
  end

  test "a tabela de colunas diz quais são obrigatórias, o formato e um exemplo da própria planilha" do
    assert_equal 10, Portfolio::SheetModel::COLUMNS.size
    assert Portfolio::SheetModel.required?("vencimento")
    assert_not Portfolio::SheetModel.required?("telefone")
    assert_equal "10/09/2026", Portfolio::SheetModel.example("vencimento")
    assert_match(/dd\/mm\/aaaa/, Portfolio::SheetModel.format_text("vencimento"))
    Portfolio::SheetModel::COLUMNS.each { |column| assert Portfolio::SheetModel.example(column).present?, column }
  end
end
