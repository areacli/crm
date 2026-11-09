require "test_helper"

# Canal dos acordos (11): a lista e as pendentes assinam o credor, a ficha assina o cliente; só quem negocia no credor (MT-3). Vem de test/system/agreements_screens_test.rb: a lista se refaz quando outra pessoa grava uma proposta.
class AgreementsChannelTest < ActionCable::Channel::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, = agreement_scenario(@alfa)
  end

  teardown { travel_back }

  test "quem negocia no credor assina o credor e o cliente" do
    stub_connection current_user: users(:carlos)
    subscribe tenant_id: @alfa.id
    assert subscription.confirmed?
    subscribe customer_id: @customer.id
    assert subscription.confirmed?
  end

  test "quem é de outro credor, quem não negocia e quem não entrou são rejeitados" do
    [ users(:marta), make_user(@alfa, []), nil ].each do |user|
      stub_connection current_user: user
      subscribe tenant_id: @alfa.id
      assert subscription.rejected?
      subscribe customer_id: @customer.id
      assert subscription.rejected?
    end
  end

  test "gravar uma proposta avisa o credor e o cliente" do
    assert_broadcasts(AgreementsChannel.broadcasting_for(@alfa), 1) do
      assert_broadcasts(AgreementsChannel.broadcasting_for(@customer), 1) { create_proposal(@customer, [ @nf1 ]) }
    end
  end
end
