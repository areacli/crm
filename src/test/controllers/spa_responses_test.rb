require "test_helper"

# Respostas da SPA (decisão 0028): o menu em JSON com as telas portadas, o 401 e o 409 que a casca trata, e o endereço retirado que volta para a casca.
class SpaResponsesTest < ActionDispatch::IntegrationTest
  TRECHO = { "X-CRM-Trecho" => "1" }.freeze

  def entrar(usuario = users(:joana)) = post(session_path, params: { email_address: usuario.email_address, password: "senha-de-teste-1" }, headers: TRECHO)

  test "a entrada pela casca responde 204, e a recusa vem em JSON" do
    post session_path, params: { email_address: users(:joana).email_address, password: "errada" }, headers: TRECHO
    assert_response :unauthorized
    assert_equal I18n.t("sessions.invalid"), response.parsed_body["erro"]

    entrar
    assert_response :no_content
  end

  test "sem sessão, o trecho recebe 401 em vez do redirecionamento" do
    get customers_path, headers: TRECHO
    assert_response :unauthorized
  end

  test "com senha temporária, o trecho recebe 409" do
    users(:joana).update!(temporary_password_until: 72.hours.from_now)
    entrar
    get menu_path, headers: TRECHO
    assert_response :conflict
  end

  test "o menu leva as janelas e o canal do sino" do
    entrar
    get menu_path, headers: TRECHO
    corpo = response.parsed_body
    assert_equal "Geral", corpo["grupos"].first["titulo"]
    assert_equal "/resumo", corpo["grupos"].first["itens"].first["caminho"]
    assert_includes corpo["janelas"], "^/titulos/\\d+$"
    assert_equal [ { "channel" => "NoticesChannel" } ], corpo["canais"]
  end

  test "o endereço de uma tela pedido como página leva à casca, com o caminho no hash; o trecho continua respondendo" do
    entrar
    cliente = Customer.where(tenant: tenants(:alfa)).first || customer_of(tenants(:alfa), FakeData.cpf(803), "Cliente Retirado")
    get customer_path(cliente, aba: "titulos")
    assert_redirected_to "/#/clientes/#{cliente.id}?aba=titulos"
    get customers_path(busca: "maria")
    assert_redirected_to "/#/clientes?busca=maria"
    get summary_path
    assert_redirected_to "/#/resumo"

    get customer_path(cliente), headers: TRECHO
    assert_response :success
    # As impressões servem página direto, fora da casca.
    get root_path
    assert_response :success
  end

  test "o redirecionamento de uma gravação pedida pela SPA vira o fim de ação, com o aviso e o destino na mesma aba" do
    sign_in_as users(:joana)
    result = ContactResult.where(tenant: tenants(:alfa)).order(:position).last
    post settings_contact_result_movement_path(result), params: { movement: { direction: "up" } }, headers: TRECHO
    assert_response :no_content
    # O fragmento do endereço (`#resultado-N`) não entra no destino da aba.
    assert_equal({ "atualizar" => true, "navegar" => "/configuracao/resultados-de-acionamento", "mesma_aba" => true }, evento_da_spa)

    # O alerta (a recusa) vai em vermelho.
    patch settings_promise_policy_path, params: { credor: tenants(:alfa).id, tenant_setting: { promise_tolerance_days: "999" } }, headers: TRECHO
    assert_response :no_content
    assert_equal "danger", evento_da_spa["tom"]
    assert_equal "/configuracao/promessas-e-acordos", evento_da_spa["navegar"]

    # A mesma gravação, pela página do servidor, continua redirecionando.
    post settings_contact_result_movement_path(result), params: { movement: { direction: "down" } }
    assert_redirected_to settings_contact_results_path(anchor: "resultado-#{result.id}")
  end
end
