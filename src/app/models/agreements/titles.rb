module Agreements
  # Os títulos do acordo (11, R221, R224): a entrada e cada parcela, criados no aceite como títulos da carteira (R225). Nascem `scheduled`: existem e podem
  # receber pagamento pelo número, mas só passam a ser cobrados (`active`) com a efetivação. O valor de cada um é distribuído pelos componentes que faltam dos
  # títulos originais, do mais antigo para o mais novo e, em cada um, na ordem da 10, R195 (R224); cada parcela soma os próprios juros do parcelamento. A
  # composição fica no título (`bills.composition`) para o motor do atraso, a baixa e o arquivo. O contrato, o produto e o cliente são os do título original
  # mais antigo (R223a, R236).
  module Titles
    module_function

    # Número do título de acordo: `ACD-000001-00` para a entrada, `-01`, `-02`... para as parcelas.
    def number_of(agreement, row_number) = format("%s-%02d", agreement.number, row_number)

    def build!(agreement)
      items = agreement.agreement_bills.includes(:bill).sort_by { |item| [ item.bill.due_date, item.bill_id ] }
      oldest = items.first.bill
      pool = items.flat_map do |item|
        after = Agreements::BASE_ORDER.to_h { |component| [ component, item.base.fetch(component, 0) - item.discount.fetch(component, 0) - item.credit.fetch(component, 0) ] }
        Agreements::BASE_ORDER.filter_map { |component| { "bill_id" => item.bill_id, "component" => component, "cents" => after[component] } if after[component].positive? }
      end
      previous_due = nil
      agreement.schedule.map do |row|
        number = row["number"].to_i
        amortization = row["amortization_cents"].to_i
        taken, pool = take(pool, amortization)
        due = Date.iso8601(row["due"])
        composition = { "items" => taken, "installment_interest" => row["interest_cents"].to_i, "period_days" => (previous_due ? (due - previous_due).to_i : 0),
                        "accrues_from" => due.iso8601, "fine" => true, "number" => number }
        previous_due = due
        Bill.create!(tenant_id: agreement.tenant_id, contract_id: oldest.contract_id, customer_id: agreement.customer_id, number: number_of(agreement, number),
                     due_date: due, amount_cents: row["amount_cents"].to_i, status: "scheduled", kind: "agreement", agreement_id: agreement.id,
                     product: oldest.product, description: description(agreement, number), composition: composition)
      end
    end

    # Tira `cents` do começo da lista de pedaços e devolve [o que foi tirado, o que sobrou].
    def take(pool, cents)
      taken = []
      rest = pool.map(&:dup)
      while cents.positive? && rest.any?
        head = rest.first
        part = [ head["cents"], cents ].min
        taken << { "bill_id" => head["bill_id"], "component" => head["component"], "cents" => part }
        head["cents"] -= part
        cents -= part
        rest.shift if head["cents"].zero?
      end
      [ taken, rest ]
    end

    def description(agreement, number) = number.zero? ? "Entrada do acordo #{agreement.number}" : "Parcela #{number} do acordo #{agreement.number}"
  end
end
