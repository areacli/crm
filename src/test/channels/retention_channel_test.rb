require "test_helper"

# A página de guarda se refaz pelo WebSocket só para quem atende os direitos do titular no credor (permissão 13, MT-3, V10); reter e
# terminar a tarefa diária transmitem o evento de invalidação.
class RetentionChannelTest < ActionCable::Channel::TestCase
  include ActiveJob::TestHelper

  setup { @alfa = tenants(:alfa) }

  test "quem tem a 13 no credor assina" do
    stub_connection current_user: users(:joana)
    subscribe tenant_id: @alfa.id

    assert subscription.confirmed?
    assert_has_stream_for @alfa
  end

  test "quem não tem a 13, quem é de outro credor e quem não está logado são rejeitados (V10)" do
    [ users(:carlos), users(:marta), nil ].each do |user|
      stub_connection current_user: user
      subscribe tenant_id: @alfa.id
      assert subscription.rejected?
    end
  end

  test "reter e a execução da tarefa transmitem retention-changed ao credor" do
    customer = make_full_customer(@alfa)

    assert_broadcasts(RetentionChannel.broadcasting_for(@alfa), 1) { Titular::Retainer.new(users(:joana)).retain(customer, "processo") }
    assert_broadcasts(RetentionChannel.broadcasting_for(@alfa), 1) { Titular::RetentionRun.new(@alfa).call }
  end
end
