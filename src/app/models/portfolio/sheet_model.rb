module Portfolio
  # Planilha-modelo da carteira (R44): o cabeçalho e três linhas fictícias válidas, que passam na conferência sem nenhuma recusa.
  # A tabela de colunas da tela de importação sai do mesmo conjunto, então o exemplo mostrado é o da planilha que se baixa.
  module SheetModel
    COLUMNS = (CsvFile::REQUIRED + CsvFile::OPTIONAL).freeze

    ROWS = [
      %w[529.982.247-25 Maria\ Souza 2026-001 10/09/2026 1.250,00] + [ "(11) 99999-0000", "maria@exemplo.com.br", "CT-100", "Mensalidade de setembro", "titular" ],
      %w[390.533.447-05 João\ Pereira 2026-002 10/10/2026 980,50] + [ "", "joao@exemplo.com.br", "CT-101", "Mensalidade de outubro", "" ],
      %w[111.444.777-35 Ana\ Lima 2026-003 15/11/2026 2.340,00] + [ "(21) 98888-7777", "", "CT-102", "Parcela do acordo", "responsável financeiro" ]
    ].freeze

    def self.required?(column) = CsvFile::REQUIRED.include?(column)

    def self.format_text(column) = I18n.t("portfolio.sheet.columns.#{column}")

    # Primeiro valor preenchido da coluna nas linhas do modelo.
    def self.example(column) = ROWS.map { |row| row[COLUMNS.index(column)] }.find(&:present?)

    # O CSV com ponto e vírgula e UTF-8 (com BOM, para o Excel reconhecer os acentos).
    def self.csv = "﻿" + ([ COLUMNS ] + ROWS).map { |row| row.join(";") }.join("\r\n") + "\r\n"
  end
end
