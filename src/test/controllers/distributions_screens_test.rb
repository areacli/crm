require "test_helper"

# Tela de distribuição (14, R311, R322, R326): distribuir pelo documento ou código, mudar, recolher com motivo; a ficha da equipe mostra com
# quem está o contrato; sem a permissão 19, nada.
class DistributionsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    @accreditation = Accreditation.find_by!(tenant: @alfa, operation: @operation)
    @ana = make_customer(@alfa, document: FakeData.cpf(401), name: "Ana Lima", contract_code: "C-7")
  end

  test "distribuir pelo documento, ver na lista e na ficha, mudar e recolher" do
    sign_in_as users(:joana)
    assert_includes rotulos_do_menu, "Distribuição"
    get distributions_url, headers: TRECHO
    assert_response :success
    post distributions_url, params: { distribution: { accreditation_id: @accreditation.id, target: "customer", value: Document.format(@ana.document), exposure: "overdue", starts_on: Date.current.iso8601 } }
    distribution = Distribution.last
    assert_equal @ana, distribution.customer
    get distributions_url, headers: TRECHO
    assert_select "tbody tr", text: /Ana Lima.*Recupera/m
    get_ficha(@ana)
    # Revisão 23: na tabela só a etiqueta; o período e a origem vão para a linha do tempo da lateral.
    assert_select "ul.operacoes-do-contrato li", text: /\ARecupera, Recupera Cobranças/
    assert_select "ol.linha-do-tempo li[data-evento=entrada]", text: /#{Regexp.escape(Date.current.strftime('%d/%m/%Y'))}.*Entrada.*Recupera.*Cliente · vencidas · à mão/m

    patch distribution_url(distribution), params: { distribution: { exposure: "all", ends_on: (Date.current + 10).iso8601 } }
    assert_equal "all", distribution.reload.exposure
    post distribution_recall_url(distribution), params: { recall: { reason: "", note: "" } }
    assert_response :unprocessable_content
    post distribution_recall_url(distribution), params: { recall: { reason: "performance", note: "" } }
    assert_equal "performance", distribution.reload.end_reason
    get_ficha(@ana)
    assert_select "ol.linha-do-tempo li", 2
    assert_select "ol.linha-do-tempo li:first-child[data-evento=saida]", text: /Saída.*Recupera.*Desempenho/m
    assert_select "ul.operacoes-do-contrato", count: 0
  end

  test "documento que não existe no credor é recusado" do
    sign_in_as users(:joana)
    post distributions_url, params: { distribution: { accreditation_id: @accreditation.id, target: "customer", value: FakeData.cpf(999) } }
    assert_response :unprocessable_content
  end

  test "sem a permissão 19, Distribuição não aparece e o endereço é recusado" do
    sign_in_as users(:carlos)
    assert_not_includes rotulos_do_menu, "Distribuição"
    get distributions_url, headers: TRECHO
    assert_response :not_found
  end


  test "17, R421: código que casa com mais de um contrato lista os encontrados, com sistema e clientes, e a pessoa escolhe" do
    sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "natural")
    twin = Contract.create!(tenant: @alfa, source_system: sap, code: "C-7")
    bia = make_customer(@alfa, document: FakeData.cpf(402), name: "Bia Reis", contract_code: "C-8")
    ContractCustomer.create!(contract: twin, customer: bia)
    sign_in_as users(:joana)
    form = { accreditation_id: @accreditation.id, target: "contract", value: "C-7", exposure: "overdue", starts_on: Date.current.iso8601 }

    assert_no_difference -> { Distribution.count } do
      post distributions_url, params: { distribution: form }, headers: painel
    end
    assert_response :unprocessable_content
    assert_includes response.body, "Há mais de um contrato com o código C-7 neste credor. Escolha um."
    assert_select "input[type=radio][name='distribution[contract_id]']", 2
    assert_select "label", text: /C-7 · Planilha · Ana Lima/
    assert_select "label", text: /C-7 · SAP · Bia Reis/

    post distributions_url, params: { distribution: form.merge(contract_id: twin.id) }, headers: painel
    assert_equal twin, Distribution.last.contract

    # O escolhido só vale para o código dele: com outro código, quem manda é o código.
    post distributions_url, params: { distribution: form.merge(value: "C-8", contract_id: twin.id) }, headers: painel
    assert_equal "C-8", Distribution.last.contract.code
  end
end
