module Portfolio
  # Planilha-modelo da carteira (R44): o cabeçalho e três linhas fictícias válidas, que passam na conferência sem nenhuma recusa.
  # A tabela de colunas da tela de importação sai do mesmo conjunto, então o exemplo mostrado é o da planilha que se baixa.
  module SheetModel
    COLUMNS = (CsvFile::REQUIRED + CsvFile::OPTIONAL).freeze

    # Colunas de contato adicionais (06): ficam depois das demais; o exemplo preenche algumas.
    CONTACT_COLUMNS = COLUMNS.drop(15)

    def self.contact_cells(**values) = CONTACT_COLUMNS.map { |column| values[column.to_sym].to_s }
    private_class_method :contact_cells

    ROWS = [
      %w[529.982.247-25 Maria\ Souza 2026-001 10/09/2026 1.250,00] + [ "(11) 99999-0000", "maria@exemplo.com.br", "CT-100", "Mensalidade de setembro", "titular", "CARTAO-GOLD", "25,00", "", "", "" ] + contact_cells(telefone2: "(11) 3333-4444", telefone3: "(11) 2222-1111", telefone4: "(11) 4444-5555", telefone5: "(11) 5555-6666", logradouro: "Rua das Flores", numero: "120", complemento: "ap 3", bairro: "Centro", cidade: "São Paulo", uf: "SP", cep: "01001-000"),
      %w[390.533.447-05 João\ Pereira 2026-002 10/10/2026 980,50] + [ "", "joao@exemplo.com.br", "CT-101", "Mensalidade de outubro", "", "", "", "12,40", "3,10", "" ] + contact_cells(email2: "joao.pereira@exemplo.com.br", email3: "joao.p@exemplo.com.br", email4: "jpereira@exemplo.com.br", email5: "pereira.joao@exemplo.com.br"),
      %w[111.444.777-35 Ana\ Lima 2026-003 15/11/2026 2.340,00] + [ "(21) 98888-7777", "", "CT-102", "Parcela do acordo", "responsável financeiro", "financiamento veicular", "", "", "", "8,00" ] + contact_cells
    ].freeze

    def self.required?(column) = CsvFile::REQUIRED.include?(column)

    def self.format_text(column) = I18n.t("portfolio.sheet.columns.#{column}")

    # Primeiro valor preenchido da coluna nas linhas do modelo.
    def self.example(column) = ROWS.map { |row| row[COLUMNS.index(column)] }.find(&:present?)

    # O CSV com ponto e vírgula e UTF-8 (com BOM, para o Excel reconhecer os acentos).
    def self.csv = "﻿" + ([ COLUMNS ] + ROWS).map { |row| row.join(";") }.join("\r\n") + "\r\n"
  end
end
