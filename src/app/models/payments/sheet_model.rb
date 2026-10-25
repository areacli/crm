module Payments
  # Colunas das planilhas de pagamentos e de estornos, para a tela e para a planilha-modelo (R44, R47). A tabela de colunas da tela e o
  # CSV baixado saem do mesmo conjunto, então o exemplo mostrado é o da planilha que se baixa.
  module SheetModel
    COLUMNS = {
      "payments" => {
        required: %w[canal identificador documento titulo data_pagamento valor meio], optional: [],
        example: { "canal" => "341-1234-56789", "identificador" => "E1234567820261019", "documento" => "529.982.247-25", "titulo" => "NF-1024/3",
                   "data_pagamento" => "18/10/2026", "valor" => "400,00", "meio" => "pix" }
      },
      "reversals" => {
        required: %w[canal identificador_pagamento identificador_estorno data_estorno valor], optional: %w[motivo],
        example: { "canal" => "341-1234-56789", "identificador_pagamento" => "E1234567820261019", "identificador_estorno" => "D9876543",
                   "data_estorno" => "20/10/2026", "valor" => "300,00", "motivo" => "contestação de cartão" }
      }
    }.freeze

    # Linhas fictícias do modelo (cabeçalho + linhas): passam na conferência quando o canal e os títulos existem.
    ROWS = {
      "payments" => [
        [ "341-1234-56789", "E1234567820261019", "529.982.247-25", "NF-1024/3", "18/10/2026", "400,00", "pix" ],
        [ "341-1234-56789", "E1234567820261020", "390.533.447-05", "NF-1025/1", "18/10/2026", "980,50", "boleto" ]
      ],
      "reversals" => [ [ "341-1234-56789", "E1234567820261019", "D9876543", "20/10/2026", "300,00", "contestação de cartão" ] ]
    }.freeze

    module_function

    def columns(kind) = COLUMNS.fetch(kind)[:required] + COLUMNS.fetch(kind)[:optional]

    def required(kind) = COLUMNS.fetch(kind)[:required]

    def optional(kind) = COLUMNS.fetch(kind)[:optional]

    def required?(kind, column) = required(kind).include?(column)

    def format_text(kind, column) = I18n.t("payments.sheet.#{kind}.#{column}")

    def example(kind, column) = COLUMNS.fetch(kind)[:example][column]

    def csv(kind) = "﻿" + ([ columns(kind) ] + ROWS.fetch(kind)).map { |row| row.join(";") }.join("\r\n") + "\r\n"
  end
end
