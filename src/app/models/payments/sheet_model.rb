module Payments
  # Colunas das planilhas de pagamentos e de estornos, para a tela e para a planilha-modelo (R44, R47). A tabela de colunas da tela e o
  # CSV baixado saem do mesmo conjunto, então o exemplo mostrado é o da planilha que se baixa.
  module SheetModel
    COLUMNS = {
      "payments" => {
        required: %w[metodo_recebimento identificador documento titulo data_pagamento valor meio], optional: %w[estado_final],
        example: { "metodo_recebimento" => "341-1234-56789", "identificador" => "E1234567820261019", "documento" => "529.982.247-25", "titulo" => "NF-1024/3",
                   "data_pagamento" => "18/10/2026", "valor" => "400,00", "meio" => "pix", "estado_final" => "quitado" }
      },
      "reversals" => {
        required: %w[metodo_recebimento identificador_pagamento identificador_estorno data_estorno valor], optional: %w[motivo],
        example: { "metodo_recebimento" => "341-1234-56789", "identificador_pagamento" => "E1234567820261019", "identificador_estorno" => "D9876543",
                   "data_estorno" => "20/10/2026", "valor" => "300,00", "motivo" => "contestação de cartão" }
      }
    }.freeze

    # Linhas fictícias do modelo (cabeçalho + linhas): passam na conferência quando o método de recebimento e os títulos existem.
    ROWS = {
      "payments" => [
        [ "341-1234-56789", "E1234567820261019", "529.982.247-25", "NF-1024/3", "18/10/2026", "400,00", "pix", "" ],
        [ "341-1234-56789", "E1234567820261020", "390.533.447-05", "NF-1025/1", "18/10/2026", "980,50", "boleto", "quitado" ]
      ],
      "reversals" => [ [ "341-1234-56789", "E1234567820261019", "D9876543", "20/10/2026", "300,00", "contestação de cartão" ] ]
    }.freeze

    # Colunas que só existem para o credor com sistema remoto (17, R416, R417): `sistema` nas duas planilhas e `id_titulo` na de pagamentos, quando algum
    # sistema é de id próprio. Sem sistema remoto, a tela e o modelo são os de sempre.
    SYSTEM_COLUMN = "sistema".freeze
    BILL_ID_COLUMN = "id_titulo".freeze
    BILL_ID_EXAMPLES = %w[T-0001 T-0002].freeze

    module_function

    # `remote`: os sistemas remotos dos credores de quem vê a tela ou baixa o modelo.
    def columns(kind, remote: []) = COLUMNS.fetch(kind)[:required] + COLUMNS.fetch(kind)[:optional] + extra_columns(kind, remote)

    # As colunas que a leitura conhece no credor da importação: `[obrigatórias, opcionais]`. Com sistema de id próprio, `titulo` deixa de ser obrigatória no
    # cabeçalho (a linha traz `id_titulo` ou `titulo`); com um só sistema, `sistema` é coluna ignorada, como qualquer outra que o arquivo traga a mais.
    def reading(kind, systems)
      required = COLUMNS.fetch(kind)[:required]
      optional = COLUMNS.fetch(kind)[:optional] + (systems.multiple? ? [ SYSTEM_COLUMN ] : [])
      return [ required, optional ] unless kind == "payments" && systems.own_ids?

      [ required - %w[titulo], optional + [ "titulo", BILL_ID_COLUMN ] ]
    end

    def required?(kind, column, remote: [])
      return false if column == "titulo" && own_ids?(remote)

      COLUMNS.fetch(kind)[:required].include?(column)
    end

    def format_text(kind, column, remote: [])
      return I18n.t("payments.sheet.payments.titulo_ou_id") if column == "titulo" && own_ids?(remote)

      I18n.t("payments.sheet.#{kind}.#{column}")
    end

    def example(kind, column, remote: [])
      return example_system(remote)&.name if column == SYSTEM_COLUMN
      return BILL_ID_EXAMPLES.first if column == BILL_ID_COLUMN

      COLUMNS.fetch(kind)[:example][column]
    end

    def csv(kind, remote: [])
      rows = ROWS.fetch(kind).each_with_index.map do |row, index|
        row + extra_columns(kind, remote).map { |column| column == SYSTEM_COLUMN ? example_system(remote).name : BILL_ID_EXAMPLES[index].to_s }
      end
      "\uFEFF" + ([ columns(kind, remote: remote) ] + rows).map { |row| row.join(";") }.join("\r\n") + "\r\n"
    end

    def extra_columns(kind, remote)
      return [] if remote.empty?

      kind == "payments" && own_ids?(remote) ? [ SYSTEM_COLUMN, BILL_ID_COLUMN ] : [ SYSTEM_COLUMN ]
    end

    def own_ids?(remote) = remote.any?(&:key_own_id?)

    # O sistema do exemplo: um de id próprio, se houver, para o `id_titulo` do modelo fazer sentido; ativo antes de pausado.
    def example_system(remote) = remote.min_by { |system| [ system.key_own_id? ? 0 : 1, system.active? ? 0 : 1, system.name ] }
  end
end
