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
    get distributions_url
    assert_response :success
    assert_select "#menu-principal a", text: "Distribuição"
    post distributions_url, params: { distribution: { accreditation_id: @accreditation.id, target: "customer", value: Document.format(@ana.document), exposure: "overdue", starts_on: Date.current.iso8601 } }
    distribution = Distribution.last
    assert_equal @ana, distribution.customer
    get distributions_url
    assert_select "tbody tr", text: /Ana Lima.*Recupera/m
    get customer_url(@ana)
    # Revisão 23: na tabela só a etiqueta; o período e a origem vão para a linha do tempo da lateral.
    assert_select "ul.operacoes-do-contrato li", text: /\ARecupera, Recupera Cobranças/
    assert_select "ol.linha-do-tempo li[data-evento=entrada]", text: /#{Regexp.escape(Date.current.strftime('%d/%m/%Y'))}.*Entrada.*Recupera.*Cliente · vencidas · à mão/m

    patch distribution_url(distribution), params: { distribution: { exposure: "all", ends_on: (Date.current + 10).iso8601 } }
    assert_equal "all", distribution.reload.exposure
    post distribution_recall_url(distribution), params: { recall: { reason: "", note: "" } }
    assert_response :unprocessable_content
    post distribution_recall_url(distribution), params: { recall: { reason: "performance", note: "" } }
    assert_equal "performance", distribution.reload.end_reason
    get customer_url(@ana)
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
    get summary_url
    assert_select "#menu-principal a", text: "Distribuição", count: 0
    get distributions_url
    assert_response :not_found
  end
end
