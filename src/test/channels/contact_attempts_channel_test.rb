require "test_helper"

# Os avisos de acionamento seguem a permissão de consultar a carteira, no credor do canal ou do cliente (MT-3).
class ContactAttemptsChannelTest < ActionCable::Channel::TestCase
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
  end

  test "quem consulta a carteira do credor assina o canal do credor" do
    stub_connection current_user: users(:carlos)

    subscribe tenant_id: @alfa.id

    assert subscription.confirmed?
    assert_has_stream_for @alfa
  end

  test "quem consulta a carteira do credor assina o canal do cliente" do
    stub_connection current_user: users(:carlos)

    subscribe customer_id: @customer.id

    assert subscription.confirmed?
    assert_has_stream_for @customer
  end

  test "quem não tem acesso ao credor é rejeitado, no canal do credor e no do cliente (V10)" do
    stub_connection current_user: users(:marta)

    subscribe tenant_id: @alfa.id
    assert subscription.rejected?

    subscribe customer_id: @customer.id
    assert subscription.rejected?
  end

  test "usuário sem a permissão 1 no credor, mesmo com vínculo, é rejeitado; conexão anônima e credor inexistente também" do
    stub_connection current_user: nil
    subscribe tenant_id: @alfa.id
    assert subscription.rejected?

    stub_connection current_user: users(:sem_vinculo)
    subscribe tenant_id: @alfa.id
    assert subscription.rejected?

    stub_connection current_user: users(:joana)
    subscribe tenant_id: 0
    assert subscription.rejected?
  end
end
