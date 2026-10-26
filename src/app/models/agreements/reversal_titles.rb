module Agreements
  # O título de estorno (11, R233, AH1, AJ2): título comum do cliente, criado pelo CRM quando um estorno muda a base em que o acordo foi aceito (crédito usado como abatimento, U1; pagamento
  # aplicado a um título antes da montagem, AF3) ou por decisão do gestor (AH2). Não integra o acordo: não quebra, não impede a quitação e não entra no mínimo. Numerado a partir do
  # acordo de origem (`ACD-000001-E1`), com a composição de origem (os pedaços de cada título original, na ordem da 10, R195) e o vencimento na data mais tardia entre a ação e o
  # processamento do estorno, mais o prazo da entrada congelado no acordo, em dia útil pelo calendário nacional (AA13, M7). Depois do vencimento, só o principal e a correção têm
  # encargos, sem multa nova (AI3): é o motor do título de acordo com `fine: false`, sobre os parâmetros de atraso congelados no acordo de origem.
  module ReversalTitles
    module_function

    def number_of(agreement, index) = "#{agreement.number}-E#{index}"

    # `items`: [{ "bill_id" =>, "component" =>, "cents" => }] já com o desconto do acordo (AG9) e os encargos até a montagem. `contract`: o do título original mais antigo.
    def create!(agreement, items:, contract:, product: nil, action_on:, processed_on:, reason: nil)
      items = items.select { |item| item["cents"].to_i.positive? }
      raise ArgumentError, "título de estorno sem valor" if items.empty?

      index = Bill.where(origin_agreement_id: agreement.id).count + 1
      from = [ action_on, processed_on ].max
      due = Charges::BusinessDays.next_business(from + agreement.terms.dig("segment", "down_payment_days").to_i)
      composition = { "items" => items, "installment_interest" => 0, "period_days" => 0, "accrues_from" => due.iso8601, "fine" => false, "number" => "E#{index}", "reason" => reason }
      bill = Bill.create!(tenant_id: agreement.tenant_id, contract_id: contract.id, customer_id: agreement.customer_id, number: number_of(agreement, index), due_date: due,
                          amount_cents: items.sum { |item| item["cents"] }, status: "active", kind: "reversal", origin_agreement_id: agreement.id, product: product || contract.bills.first&.product,
                          description: "Título de estorno do acordo #{agreement.number}", composition: composition)
      AgreementEvent.log!(agreement, "reversal_title", data: { "number" => bill.number, "amount_cents" => bill.amount_cents })
      Change.record!(tenant_id: agreement.tenant_id, subject_type: "bill", subject_id: bill.id, event: "reversal_title_created", after: bill.amount_cents.to_s)
      bill
    end

    # O estorno que reabre um título de acordo no prazo novo (N10): a data de onde contam os dias de quebra.
    def reopened_on(action_on, processed_on) = [ action_on, processed_on ].max
  end
end
