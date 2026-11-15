module Cadences
  # Como a régua escreve uma ação e um objeto (21, R432, R440; protótipo): "SMS · Lembrete atraso", "Proposta · à vista · concessão máxima",
  # "Pix · vence em 3 dias · faturas vencidas", "C-77". Serve às telas, ao detalhe do executor simulado e à coleção `comandos`.
  module Labels
    module_function

    def kind(kind) = I18n.t("cadences.kinds.#{kind}")

    def parameter(action)
      case action.kind
      when *Catalog::COMMUNICATIONS.keys then action.message_piece&.name
      when "task" then action.queue_task&.name
      when "proposal" then [ I18n.t("cadences.proposal_forms.#{action.params['form']}"), I18n.t("cadences.proposal_concessions.#{action.params['concession']}") ].join(" · ")
      when "promise" then I18n.t("cadences.promise_values.#{action.params['value']}")
      when "issue_instrument"
        [ I18n.t("cadences.issue_due", count: action.params["due_days"].to_i), I18n.t("cadences.issue_objects.#{action.params['object']}"),
          (I18n.t("cadences.reissue") if action.params["reissue"]) ].compact.join(" · ")
      end
    end

    # O tipo, ou o meio na emissão, com o parâmetro.
    def action(action)
      head = action.kind == "issue_instrument" ? PaymentMethod.label(action.payment_method) : kind(action.kind)
      [ head, parameter(action) ].compact_blank.join(" · ")
    end

    # O objeto sem dado pessoal: o código do contrato, o número da fatura com o contrato, ou o número do cliente no CRM.
    def object(decision)
      if decision.bill_id then "#{decision.bill&.number} · #{decision.bill&.contract&.code || I18n.t('cadences.contract_without_code')}"
      elsif decision.contract_id then decision.contract&.code || I18n.t("cadences.contract_number", id: decision.contract_id)
      else I18n.t("cadences.customer_number", id: decision.customer_id)
      end
    end
  end
end
