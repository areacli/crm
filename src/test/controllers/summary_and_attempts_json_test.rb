require "test_helper"

# Resumo da carteira e lista de acionamentos em JSON para a SPA (R23, R78; decisão 0025).
class SummaryAndAttemptsJsonTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @cliente = Customer.create!(tenant: @alfa, document: "52998224725", name: "Maria Souza")
    contrato = Contract.create!(tenant: @alfa, code: "C-1")
    ContractCustomer.create!(contract: contrato, customer: @cliente, roles: %w[holder financial_responsible])
    Bill.create!(tenant: @alfa, contract: contrato, customer: @cliente, number: "T1", due_date: Date.current - 40, amount_cents: 10_000)
  end

  test "o resumo traz os indicadores com a definição e os dados de cada cartão" do
    sign_in_as users(:joana)
    get summary_url(format: :json)

    assert_response :success
    resumo = response.parsed_body
    vencido = resumo["indicadores"].find { |indicador| indicador["rotulo"] == "Vencido" }
    assert_equal "R$ 100,00", vencido["valor"]
    assert vencido["definicao"].present?
    assert_equal "Aceitos", resumo.dig("acordos_por_mes", "linhas", 0, "situacao")
    acionamentos = resumo["acionamentos"]
    assert_equal acionamentos["colunas"].size, acionamentos["linhas"].first["celulas"].size
    assert_equal resumo.dig("promessas", "colunas").size, resumo.dig("promessas", "linhas", 0, "celulas").size
  end

  test "a lista de acionamentos traz o período padrão, os filtros e as linhas; o filtro por canal vale" do
    sign_in_as users(:joana)
    post customer_contact_attempts_url(@cliente), params: { contact_attempt: { channel: "phone", result_id: contact_results(:alfa_no_answer).id } }, as: :json

    get contact_attempts_url(format: :json)
    lista = response.parsed_body
    assert_equal (Date.current - 7).iso8601, lista["de"]
    assert_equal [ "Maria Souza" ], lista["linhas"].map { |linha| linha["cliente"] }
    assert_equal "Telefone", lista["linhas"].first["canal"]

    get contact_attempts_url(format: :json, channel: "email")
    assert_empty response.parsed_body["linhas"]
  end

  test "MT-3: o operador de outro credor não vê os acionamentos do Alfa" do
    sign_in_as users(:joana)
    post customer_contact_attempts_url(@cliente), params: { contact_attempt: { channel: "phone", result_id: contact_results(:alfa_no_answer).id } }, as: :json
    sign_in_as users(:marta)

    get contact_attempts_url(format: :json)
    assert_empty response.parsed_body["linhas"]
  end
end
