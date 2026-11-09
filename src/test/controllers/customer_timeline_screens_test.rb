require "test_helper"

# Linha do tempo da ficha (padrões de interface, revisão 24): o trecho do htmx, a volta à ficha sem JavaScript e a recusa para quem não vê o cliente.
class CustomerTimelineScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    insert_attempt(@customer, contacted_at: 2.hours.ago)
  end

  test "o trecho traz só o cartão; sem htmx volta à ficha com os mesmos parâmetros" do
    sign_in_as users(:joana)
    get customer_timeline_url(@customer, linha: "atendimento"), headers: htmx
    assert_response :success
    assert_select "section#linha-do-tempo ol.linha-do-tempo li[data-evento=atendimento]", 1
    assert_select ".filtro-em-pilulas a[aria-current=true]", text: "Atendimento"
    assert_select "details.usuario", count: 0

    # Na SPA (decisão 0028), o mesmo trecho, pelo `X-CRM-Trecho`; e a ficha com os parâmetros abre no filtro dela.
    get customer_timeline_url(@customer, linha: "atendimento"), headers: TRECHO
    assert_select "section#linha-do-tempo li[data-evento=atendimento]", 1
    assert_select ".aba-raiz, .ficha", count: 0
    get_ficha(@customer, linha: "atendimento")
    assert_select "#linha-do-tempo .filtro-em-pilulas a[aria-current=true]", text: "Atendimento"
  end

  test "quem não vê o cliente recebe 404" do
    sign_in_as make_user(tenants(:beta), %w[view_portfolio])
    get customer_timeline_url(@customer), headers: htmx
    assert_response :not_found
  end
end
