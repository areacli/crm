# Acionamentos para os testes: cliente pronto, registro direto no banco e os resultados da lista inicial (fixtures `contact_results`).
module ContactsHelper
  # Cliente da Alfa (ou do credor dado) com um título; devolve o cliente.
  def make_customer(tenant = tenants(:alfa), document: PaymentsHelper::MARIA, name: "Maria Souza", contract_code: "CT-1")
    make_bill(tenant, document: document, name: name, contract_code: contract_code, number: "NF-#{document.delete('^0-9')}").customer
  end

  # Resultado da lista inicial do credor por chave (ver `test/fixtures/contact_results.yml`): contact_results(:alfa_no_answer).
  def result_of(tenant, key) = contact_results(:"#{tenant.id == tenants(:alfa).id ? 'alfa' : 'beta'}_#{key}")

  def attempt_attributes(customer, user, overrides = {})
    result = overrides.delete(:result) || result_of(customer.tenant, :no_answer)
    { channel: "phone", result_id: result.id, contact_used: nil, text: nil, contacted_at: nil, return_at: nil, contract_id: nil }.merge(overrides)
  end

  # Registra pelo gerenciador, como a tela faz.
  def record_attempt(customer, user = users(:joana), overrides = {})
    Contacts::Recorder.new(user).record(customer, attempt_attributes(customer, user, overrides))
  end

  # Grava direto, com a data do contato e o operador escolhidos (sem passar pelas regras): para montar listas e resumos.
  def insert_attempt(customer, user: users(:joana), result: nil, contacted_at: 1.hour.ago, channel: "phone", text: nil)
    result ||= result_of(customer.tenant, :no_answer)
    ContactAttempt.create!(tenant_id: customer.tenant_id, customer: customer, user: user, result: result, result_kind: result.kind, channel: channel,
                           contacted_at: contacted_at, text: text)
  end

  def htmx = { "HX-Request" => "true" }
end
