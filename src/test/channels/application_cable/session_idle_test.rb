require "test_helper"

# A conexão do WebSocket recusa a sessão parada por 30 minutos (R28). Vem de sessions_controller_test.
class ApplicationCable::SessionIdleTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "sessão sem atividade há 31 minutos não identifica ninguém" do
    session = users(:joana).sessions.create!(updated_at: 31.minutes.ago)
    cookies.signed[:session_id] = session.id
    connect
    assert_nil connection.current_user
  end

  test "sessão com atividade há 29 minutos identifica a pessoa" do
    session = users(:joana).sessions.create!(updated_at: 29.minutes.ago)
    cookies.signed[:session_id] = session.id
    connect
    assert_equal users(:joana), connection.current_user
  end
end
