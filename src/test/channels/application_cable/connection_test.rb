require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "com sessão válida, a conexão sabe quem é o usuário" do
    session = users(:joana).sessions.create!
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:joana), connection.current_user
  end

  test "sem sessão a conexão é aceita, anônima (cada canal decide)" do
    connect

    assert_nil connection.current_user
  end

  test "sessão vencida não identifica ninguém" do
    session = users(:joana).sessions.create!(created_at: 9.hours.ago)
    cookies.signed[:session_id] = session.id

    connect

    assert_nil connection.current_user
  end
end
