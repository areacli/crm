module Payments
  # Valida um registro canônico de pagamento (R49, R52a; 17, R416 e R417), venha de arquivo, de webhook ou de instrumento pago. Devolve
  # [linha normalizada, nil] ou [nil, motivo da recusa].
  class PaymentRowValidator
    ParsedRow = Data.define(:line, :channel_code, :identifier, :document, :bill_number, :paid_on, :amount_cents, :payment_method, :final_state,
                            :source_system_id, :external_bill_id, :target_bill_id)

    FIELD_NAMES = { "metodo_recebimento" => "método de recebimento", "identificador" => "identificador", "documento" => "documento", "data_pagamento" => "data de pagamento",
                    "valor" => "valor", "meio" => "meio" }.freeze

    # `systems`: os sistemas do credor (`Payments::Systems`), lidos uma vez por arquivo ou por evento.
    def initialize(systems)
      @systems = systems
    end

    # `own`: pagamento de instrumento emitido pelo CRM (17, R417b): não declara sistema e o pai é o CRM. `target_bill_id`: o título a que o instrumento foi
    # emitido, quando foi a um título; a baixa vai nele, sem procurar pelo número.
    def validate(record, own: false, target_bill_id: nil)
      values = record.raw
      return [ nil, "linha com mais colunas que o cabeçalho" ] if record.extra
      return [ nil, "linha incompleta" ] if record.short

      FIELD_NAMES.each { |field, label| return [ nil, "#{label} obrigatório" ] if values[field].blank? }
      number = values["titulo"].presence
      system, reason = own ? [ nil, nil ] : @systems.of_line(values["sistema"], internal: Promises.number?(number) || Agreements.number?(number))
      return [ nil, reason ] if reason

      # R417: o id do título só existe em sistema de id próprio; em chave natural (e na linha sem sistema) a coluna é ignorada.
      external_id = values["id_titulo"].presence if system&.key_own_id?
      # R52a: todo pagamento identifica um título; sem ele a linha é recusada.
      return [ nil, "título não informado" ] if number.nil? && external_id.nil? && target_bill_id.nil?
      return [ nil, "identificador acima de 200 caracteres" ] if values["identificador"].length > 200
      return [ nil, "método de recebimento ou título acima de 100 caracteres" ] if values["metodo_recebimento"].length > 100 || number.to_s.length > 100
      return [ nil, "id do título acima de 100 caracteres" ] if external_id.to_s.length > 100

      problem = Document.problem(values["documento"])
      return [ nil, problem ] if problem

      problems = record.format_problems
      return [ nil, problems[:paid_on] ] if problems[:paid_on]
      return [ nil, "data de pagamento futura" ] if record.paid_on > Date.current

      %i[amount payment_method final_state].each { |field| return [ nil, problems[field] ] if problems[field] }

      [ ParsedRow.new(line: record.position, channel_code: values["metodo_recebimento"], identifier: values["identificador"], document: record.document,
                      bill_number: number, paid_on: record.paid_on, amount_cents: record.amount_cents, payment_method: record.payment_method, final_state: record.final_state,
                      source_system_id: system&.id, external_bill_id: external_id, target_bill_id: target_bill_id), nil ]
    end
  end
end
