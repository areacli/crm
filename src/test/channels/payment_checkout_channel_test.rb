require "test_helper"

# Canal por token da página pública (12, R277): sem login, autorizado pelo token; só o sinal de que o estado mudou.
class PaymentCheckoutChannelTest < ActionCable::Channel::TestCase
  setup do
    @alfa = tenants(:alfa)
    @checkout = make_checkout(customer: make_customer(@alfa))
  end

  test "quem tem o token assina, sem login" do
    stub_connection current_user: nil
    subscribe token: @checkout.token

    assert subscription.confirmed?
    assert_has_stream_for @checkout
  end

  test "token inexistente, vencido ou de link cancelado é rejeitado igual (V10)" do
    expired = make_checkout(customer: Customer.find_by(tenant_id: @alfa.id), expires_at: 1.second.from_now)
    expired.update_columns(expires_at: 1.minute.ago)
    canceled = make_checkout(customer: Customer.find_by(tenant_id: @alfa.id))
    canceled.update_columns(state: "canceled")
    [ "nada", "", expired.token, canceled.token, nil ].each do |token|
      stub_connection current_user: nil
      subscribe token: token
      assert subscription.rejected?, token.inspect
    end
  end

  test "o canal de um link não recebe o aviso de outro" do
    other = make_checkout(customer: Customer.find_by(tenant_id: @alfa.id))
    stub_connection current_user: nil
    subscribe token: @checkout.token
    assert_has_stream_for @checkout
    assert_not_equal PaymentCheckoutChannel.broadcasting_for(@checkout), PaymentCheckoutChannel.broadcasting_for(other)
    assert_no_match(/#{Regexp.escape(@checkout.token)}/, PaymentCheckoutChannel.broadcasting_for(@checkout), "o nome do fluxo não leva o token")
  end

  test "o aviso leva só checkout-changed, sem dado nenhum" do
    assert_broadcast_on(PaymentCheckoutChannel.broadcasting_for(@checkout), { "event" => "checkout-changed" }) { Payments::Checkouts.broadcast(@checkout) }
  end
end
