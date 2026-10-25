require "test_helper"

# Canais de tempo real da busca de índices e do recálculo de segmentos: só para quem vê a tela (V10); sem polling.
class IndexesAndSegmentsChannelsTest < ActionCable::Channel::TestCase
  tests IndexesChannel

  test "índices: quem consulta, configura ou muda políticas em algum credor assina; quem não está logado ou não tem vínculo, não" do
    stub_connection current_user: users(:carlos)
    subscribe
    assert subscription.confirmed?
    assert_has_stream IndexesChannel.broadcasting_for("all")

    [ users(:sem_vinculo), nil ].each do |user|
      stub_connection current_user: user
      subscribe
      assert subscription.rejected?
    end
  end
end

class SegmentsChannelTest < ActionCable::Channel::TestCase
  tests SegmentsChannel

  test "segmentos: quem tem a 4 ou a 14 no credor assina; o operador, o de outro credor e quem não está logado são rejeitados" do
    stub_connection current_user: users(:joana)
    subscribe tenant_id: tenants(:alfa).id
    assert subscription.confirmed?
    assert_has_stream_for tenants(:alfa)

    [ users(:carlos), users(:marta), nil ].each do |user|
      stub_connection current_user: user
      subscribe tenant_id: tenants(:alfa).id
      assert subscription.rejected?
    end
  end
end
