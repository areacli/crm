require "test_helper"

# O canal de avisos é do usuário da conexão: não aceita parâmetro, então ninguém assina o de outra pessoa.
class NoticesChannelTest < ActionCable::Channel::TestCase
  test "o usuário logado assina o canal dos próprios avisos" do
    stub_connection current_user: users(:carlos)

    subscribe

    assert subscription.confirmed?
    assert_has_stream_for users(:carlos)
  end

  test "pedir o canal de outro usuário por parâmetro não muda nada: o stream continua o do dono da conexão" do
    stub_connection current_user: users(:carlos)

    subscribe user_id: users(:joana).id

    assert_has_stream_for users(:carlos)
    assert_equal [ NoticesChannel.broadcasting_for(users(:carlos)) ], subscription.streams
  end

  test "conexão anônima é rejeitada" do
    stub_connection current_user: nil

    subscribe

    assert subscription.rejected?
  end
end
