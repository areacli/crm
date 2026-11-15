module Payments
  # Valida um registro canônico de estorno (R60, R61; 17, R416). Devolve [linha normalizada, nil] ou [nil, motivo da recusa].
  class ReversalRowValidator
    ParsedRow = Data.define(:line, :payment_method, :provider, :provider_name, :account_key, :account_code, :payment_identifier, :identifier, :paid_on, :amount_cents, :reason, :source_system_id)

    FIELD_NAMES = { "meio" => "meio", "fornecedor" => "fornecedor", "conta" => "conta", "identificador_pagamento" => "identificador do pagamento", "identificador_estorno" => "identificador do estorno",
                    "data_estorno" => "data do estorno", "valor" => "valor" }.freeze

    # `systems`: os sistemas do credor (`Payments::Systems`), lidos uma vez por arquivo.
    def initialize(systems)
      @systems = systems
    end

    def validate(record)
      values = record.raw
      return [ nil, "linha com mais colunas que o cabeçalho" ] if record.extra
      return [ nil, "linha incompleta" ] if record.short

      FIELD_NAMES.each { |field, label| return [ nil, "#{label} #{field == "conta" ? "obrigatória" : "obrigatório"}" ] if values[field].blank? }
      return [ nil, "identificador ou fornecedor acima do limite" ] if values["identificador_estorno"].length > 200 || values["identificador_pagamento"].length > 200 ||
                                                                     values["fornecedor"].strip.length > 100 || values["conta"].strip.length > 100
      # 03, revisão 12 (R60, R61): o meio e o fornecedor do pagamento estornado, que com o identificador acham o pagamento.
      method = PaymentMethod.from_sheet(values["meio"])
      return [ nil, "meio de pagamento fora da lista" ] unless method
      provider = PaymentProvider.key(values["fornecedor"])
      return [ nil, "fornecedor obrigatório" ] if provider.empty?
      account = PaymentProvider.account_key(values["conta"])
      return [ nil, "conta obrigatória" ] if account.empty?
      return [ nil, "motivo acima de 300 caracteres" ] if values["motivo"].to_s.length > 300

      # R416: o sistema declarado precisa existir e estar ativo; se é o do pagamento estornado, a conferência diz depois, com o pagamento à mão.
      system, reason = @systems.declared(values["sistema"])
      return [ nil, reason ] if reason

      problems = record.format_problems
      return [ nil, problems[:paid_on] ] if problems[:paid_on]
      return [ nil, "data de estorno futura" ] if record.paid_on > Date.current
      return [ nil, problems[:amount] ] if problems[:amount]

      [ ParsedRow.new(line: record.position, payment_method: method, provider: provider, provider_name: values["fornecedor"].strip, account_key: account, account_code: values["conta"].strip, payment_identifier: values["identificador_pagamento"],
                      identifier: values["identificador_estorno"], paid_on: record.paid_on, amount_cents: record.amount_cents, reason: values["motivo"].presence,
                      source_system_id: system&.id), nil ]
    end
  end
end
