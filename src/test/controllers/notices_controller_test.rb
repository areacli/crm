require "test_helper"

# Sino de avisos (A5, R36a): lista os não lidos do próprio usuário e marca como lido. Na casca (fase 8 do port), o contador vem do `menu.json`, com o canal do
# usuário, e a lista abre numa janela (`/avisos`, trecho).
class NoticesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @notice = Notice.create!(user: users(:carlos), kind: "linked_to_tenant", data: { tenant_name: "Escola Alfa", actor_name: "Joana Souza", profile_name: "Gestor" })
    @alheio = Notice.create!(user: users(:joana), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Operador" })
  end

  test "o menu da casca traz o contador e o canal de avisos; a janela traz o texto do aviso, só do próprio usuário" do
    sign_in_as users(:carlos)

    get menu_path(format: :json)
    assert_equal 1, response.parsed_body["avisos"]
    assert_includes response.parsed_body["canais"], { "channel" => "NoticesChannel" }

    get notices_url, headers: TRECHO
    assert_response :success
    assert_select "strong", "Joana Souza ligou você a Escola Alfa"
    assert_select "p", "Perfil: Gestor."
    assert_select "h1", count: 0
    assert_not_includes response.body, "Clínica Beta"
  end

  test "sem aviso novo a janela diz isso e o menu não conta nada" do
    @notice.read!
    sign_in_as users(:carlos)

    get notices_url, headers: TRECHO
    assert_select "p.vazio", "Nenhum aviso novo."
    get menu_path(format: :json)
    assert_equal 0, response.parsed_body["avisos"]
  end

  test "marcar como lido; o aviso de outro usuário não se marca" do
    sign_in_as users(:carlos)

    patch notice_url(@notice), headers: TRECHO
    assert_response :no_content
    assert_not_nil @notice.reload.read_at

    patch notice_url(@alheio), headers: TRECHO
    assert_response :not_found
    assert_nil @alheio.reload.read_at
  end

  test "marcar todos como lidos" do
    Notice.create!(user: users(:carlos), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Operador" })
    sign_in_as users(:carlos)

    post notices_reading_url, headers: TRECHO

    assert_response :no_content
    assert_equal 0, users(:carlos).notices.unread.count
    assert_nil @alheio.reload.read_at
  end

  test "criar o aviso transmite o sinal ao canal do próprio usuário" do
    stream = NoticesChannel.broadcasting_for(users(:marta))

    assert_broadcasts stream, 1 do
      Notice.create!(user: users(:marta), kind: "linked_to_tenant", data: { tenant_name: "Escola Alfa", actor_name: "Joana Souza", profile_name: "Gestor" })
    end
  end

  test "a ligação pela tela cria o aviso 'foi ligado ao credor' para a pessoa (R36a)" do
    sign_in_as users(:joana)
    post memberships_url, params: { membership: { tenant_id: tenants(:alfa).id, email_address: "marta@exemplo.com.br", name: "", profile_id: profiles(:alfa_manager).id } }

    sign_in_as users(:marta)
    get notices_url, headers: TRECHO
    assert_select "strong", "Joana Souza ligou você a Escola Alfa"
    assert_select "p", "Perfil: Gestor."
  end

  test "sem sessão a janela não responde" do
    get notices_url, headers: TRECHO

    assert_response :unauthorized
  end
end
