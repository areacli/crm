require "test_helper"

# Canal das promessas (10, R203, R204): a ficha assina o cliente e a lista, o credor; só quem consulta a carteira no credor (MT-3).
class PromisesChannelTest < ActionCable::Channel::TestCase
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
  end

  test "quem consulta a carteira assina o credor e o cliente" do
    stub_connection current_user: users(:carlos)
    subscribe tenant_id: @alfa.id
    assert subscription.confirmed?
    subscribe customer_id: @customer.id
    assert subscription.confirmed?
  end

  test "quem não tem acesso ao credor é rejeitado" do
    stub_connection current_user: users(:marta)
    subscribe tenant_id: @alfa.id
    assert subscription.rejected?
    subscribe customer_id: @customer.id
    assert subscription.rejected?
  end

  test "mudar a promessa transmite o evento ao credor e aos clientes do contrato" do
    customer, nf1, = promise_scenario(@alfa, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-J", name: "João")
    assert_broadcasts(PromisesChannel.broadcasting_for(@alfa), 1) { Promises::Broadcast.changed(@alfa, [ customer.id ]) }
    assert_broadcasts(PromisesChannel.broadcasting_for(customer), 1) { Promises::Broadcast.changed(@alfa, [ customer.id ]) }
    assert_equal customer, nf1.customer
  end
end
