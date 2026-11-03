require "test_helper"

# Lista de clientes e ficha em JSON para a SPA (R21, R22; decisão 0025): os mesmos dados das páginas do servidor, por credor.
class CustomersJsonTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper
  setup do
    @alfa = tenants(:alfa)
    @cliente = Customer.create!(tenant: @alfa, document: "52998224725", name: "Maria Souza")
    contrato = Contract.create!(tenant: @alfa, code: "C-1")
    ContractCustomer.create!(contract: contrato, customer: @cliente, roles: %w[holder financial_responsible])
    Bill.create!(tenant: @alfa, contract: contrato, customer: @cliente, number: "T1", due_date: Date.current - 40, amount_cents: 10_000)
    @beta_cliente = Customer.create!(tenant: tenants(:beta), document: "11144477735", name: "Cliente do Beta")
  end

  test "a lista traz as linhas da página, a paginação, os filtros e o que a pessoa pode fazer" do
    sign_in_as users(:joana)
    get customers_url(format: :json, per_page: 20)

    assert_response :success
    corpo = response.parsed_body
    assert_equal [ "Maria Souza" ], corpo["linhas"].map { |linha| linha["nome"] }
    assert_equal 1, corpo["total"]
    assert_equal 20, corpo["por_pagina"]
    linha = corpo["linhas"].first
    assert_equal "R$ 100,00", linha["vencido"]
    assert_includes linha["pode"].keys, "registrar_acionamento"
    assert corpo["filtros"]["faixas"].any?
  end

  test "a busca filtra pelo nome, como na página do servidor" do
    sign_in_as users(:joana)
    get customers_url(format: :json, q: "ninguém com este nome")

    assert_equal 0, response.parsed_body["total"]
  end

  test "MT-3: cada credor só vê os próprios clientes; a ficha de outro credor responde 404" do
    sign_in_as users(:marta)
    get customers_url(format: :json)
    assert_not_includes response.parsed_body["linhas"].map { |linha| linha["nome"] }, "Maria Souza"

    get customer_url(@cliente, format: :json)
    assert_response :not_found
  end

  test "a ficha traz o cabeçalho, os contratos, os títulos e a lateral" do
    sign_in_as users(:joana)
    get customer_url(@cliente, format: :json)

    assert_response :success
    ficha = response.parsed_body
    assert_equal "Maria Souza", ficha["nome"]
    assert_equal [ "T1" ], ficha["titulos"].map { |titulo| titulo["numero"] }
    assert_equal "Vencido", ficha["titulos"].first["situacao"]
    assert_equal "Error", ficha["titulos"].first["situacao_estado"]
    assert_equal "R$ 100,00", ficha.dig("em_cobranca", "vencido")
    assert_equal 1, ficha.dig("abas", "titulos")
    assert(ficha["indicadores"].any? { |indicador| indicador["texto"].start_with?("Atraso de") })
  end

  test "a linha do tempo da ficha vem em JSON, com o filtro e a página; sem eventos, a frase de vazio" do
    sign_in_as users(:joana)
    get customer_timeline_url(@cliente, format: :json)

    assert_response :success
    linha = response.parsed_body
    assert_equal [], linha["eventos"]
    assert_equal "Nenhum evento para este cliente.", linha["vazio"]
    assert_equal 1, linha["pagina"]
    assert_includes linha["tipos"], "atendimento"
  end

  test "registrar acionamento pela SPA: o formulário em JSON reage ao resultado, e o registro responde JSON (04, R73)" do
    sign_in_as users(:joana)
    get form_customer_contact_attempts_url(@cliente, format: :json)
    assert_response :success
    formulario = response.parsed_body
    assert_includes formulario["resultados"].map { |resultado| resultado["nome"] }, contact_results(:alfa_call_back).name
    assert_nil formulario["retorno"]

    get new_customer_contact_attempt_url(@cliente, format: :json, contact_attempt: { channel: "phone", result_id: contact_results(:alfa_call_back).id })
    assert_not_nil response.parsed_body["retorno"], "o resultado escolhido aceita o retorno combinado"

    assert_difference -> { ContactAttempt.count } => 1 do
      post customer_contact_attempts_url(@cliente), params: { contact_attempt: { channel: "phone", result_id: contact_results(:alfa_no_answer).id } }, as: :json
    end
    assert_response :created
    assert_equal "Acionamento registrado.", response.parsed_body["mensagem"]
  end

  test "acionamento recusado responde 422 com a mensagem, e nada é gravado" do
    sign_in_as users(:joana)
    assert_no_difference -> { ContactAttempt.count } do
      post customer_contact_attempts_url(@cliente), params: { contact_attempt: { channel: "phone", result_id: "" } }, as: :json
    end
    assert_response :unprocessable_content
    assert response.parsed_body["mensagem"].present?
  end

  test "tempo real (decisão 0025): o acionamento novo publica o cliente, e quem está presente recebe a linha dele" do
    Rails.cache.clear
    sign_in_as users(:joana)
    Live::Presence.enter(users(:joana))

    assert_enqueued_with(job: LiveBroadcastJob, args: [ "clientes", [ @cliente.id ], @alfa.id ]) do
      post customer_contact_attempts_url(@cliente), params: { contact_attempt: { channel: "phone", result_id: contact_results(:alfa_no_answer).id } }, as: :json
    end
    LiveBroadcastJob.perform_now("clientes", [ @cliente.id ], @alfa.id)
    mensagem = JSON.parse(broadcasts(LiveChannel.broadcasting_for(users(:joana))).last)
    assert_equal [ "Maria Souza" ], mensagem["registros"].map { |cliente| cliente["nome"] }
  end
end
