# Promessas para os testes (10): o contrato da Maria com os títulos NF-1 (R$ 1.000,00, vencido em 15/07/2026) e NF-2 (R$ 500,00, vencido em 15/09/2026), os
# encargos do exemplo da especificação (multa 2%, juros 1% ao mês, IPCA) e o registro da promessa como o formulário faz.
module PromisesTestHelper
  PROMISED = Date.new(2026, 10, 30)

  # Maria com NF-1 e NF-2 no contrato CT-1 do credor; devolve [cliente, NF-1, NF-2]. Com `charges`, o credor tem a regra do exemplo e os índices de 2026.
  def promise_scenario(tenant = tenants(:alfa), charges: true, document: PaymentsHelper::MARIA, contract_code: "CT-1", name: "Maria Souza")
    if charges
      seed_indexes! if IndexRate.none?
      configure_charges(tenant)
    end
    first = make_bill(tenant, number: "NF-1", amount_cents: 100_000, document: document, contract_code: contract_code, due: ChargesTestHelper::DUE, name: name)
    second = make_bill(tenant, number: "NF-2", amount_cents: 50_000, document: document, contract_code: contract_code, due: Date.new(2026, 9, 15), name: name)
    [ first.customer, first, second ]
  end

  # Registra a promessa pelo acionamento, como a tela: devolve a promessa.
  def register_promise(customer, bills, user: users(:joana), on: PROMISED, method: "pix", result: :promised, **overrides)
    contract_id = overrides.delete(:promise_contract_id) || bills.first&.contract_id
    attempt = record_attempt(customer, user, result: result_of(customer.tenant, result), promise_contract_id: contract_id,
                                              promise_bill_ids: bills.map { |bill| bill.id.to_s }, promise_payment_method: method, promise_on: on.iso8601, **{ text: SecureRandom.hex(4) }.merge(overrides))
    attempt.promise
  end

  def travel_day(date, &block) = travel_to(date.in_time_zone.change(hour: 12), &block)

  def refuse_message(&block) = assert_raises(Promises::Refused, &block).message
end
