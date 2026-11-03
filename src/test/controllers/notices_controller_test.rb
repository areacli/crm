require "test_helper"

# Sino de avisos (A5, R36a): lista os não lidos do próprio usuário e marca como lido.
class NoticesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @notice = Notice.create!(user: users(:carlos), kind: "linked_to_tenant", data: { tenant_name: "Escola Alfa", actor_name: "Joana Souza", profile_name: "Gestor" })
    @alheio = Notice.create!(user: users(:joana), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Operador" })
  end

  test "o cabeçalho tem o sino com o contador e o texto do aviso, e assina o canal de avisos" do
    sign_in_as users(:carlos)

    get root_url

    assert_select "#sino[hx-trigger*='cable:notice-created']"
    assert_select "#sino .contador", "1"
    assert_select "#sino strong", "Joana Souza ligou você a Escola Alfa"
    assert_select "#sino small", "Perfil: Gestor."
    assert_select "meta[name=cable-channels][content*=NoticesChannel]"
    assert_not_includes response.body, "Clínica Beta"
  end

  test "sem aviso novo o sino diz isso e não mostra contador" do
    @notice.read!
    sign_in_as users(:carlos)

    get root_url

    assert_select "#sino .contador", count: 0
    assert_select "#sino p", "Nenhum aviso novo."
  end

  test "o htmx busca só o sino; a página inteira não é refeita" do
    sign_in_as users(:carlos)

    get notices_url, headers: { "HX-Request" => "true" }

    assert_response :success
    assert_select "#sino"
    assert_select "header", false
  end

  test "marcar como lido atualiza o sino; o aviso de outro usuário não se marca" do
    sign_in_as users(:carlos)

    patch notice_url(@notice), headers: { "HX-Request" => "true" }
    assert_response :success
    assert_select "#sino .contador", count: 0
    assert_not_nil @notice.reload.read_at

    patch notice_url(@alheio), headers: { "HX-Request" => "true" }
    assert_response :not_found
    assert_nil @alheio.reload.read_at
  end

  test "marcar todos como lidos" do
    Notice.create!(user: users(:carlos), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Operador" })
    sign_in_as users(:carlos)

    post notices_reading_url, headers: { "HX-Request" => "true" }

    assert_response :success
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
    get root_url
    assert_select "#sino strong", "Joana Souza ligou você a Escola Alfa"
    assert_select "#sino small", "Perfil: Gestor."
  end

  test "sem sessão o sino não responde" do
    get notices_url, headers: { "HX-Request" => "true" }

    assert_redirected_to new_session_url
  end
end
