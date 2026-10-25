require "test_helper"

class PlatformChannelTest < ActionCable::Channel::TestCase
  test "qualquer conexão, até anônima, assina o canal da plataforma" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream PlatformChannel::STREAM
  end
end
