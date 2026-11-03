require "test_helper"

# Tempo real com dados (decisão 0025): um fluxo por usuário, presença contada por conexão, e a mensagem montada no contexto de quem a
# recebe. Os recursos de cada tela entram nos testes da tela; aqui, um recurso de teste sobre os clientes.
class LiveChannelTest < ActionCable::Channel::TestCase
  setup { Rails.cache.clear }

  test "o usuário assina o próprio fluxo e fica presente enquanto houver conexão" do
    stub_connection current_user: users(:joana)

    subscribe
    assert subscription.confirmed?
    assert_has_stream_for users(:joana)
    assert Live::Presence.present?(users(:joana).id)

    unsubscribe
    assert_not Live::Presence.present?(users(:joana).id)
  end

  test "sem usuário, ou com senha temporária, a assinatura é recusada" do
    stub_connection current_user: nil
    subscribe
    assert subscription.rejected?

    users(:carlos).update!(temporary_password_until: 72.hours.from_now)
    stub_connection current_user: users(:carlos)
    subscribe
    assert subscription.rejected?
  end
end

class LiveBroadcastJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    Rails.cache.clear
    ApplicationController.prepend_view_path(Rails.root.join("test/views"))
    Live.register("clientes_teste", partial: "live_teste/clientes") { |user, ids| Customer.where(id: ids, tenant_id: user.tenant_ids_with("view_portfolio")) }
  end

  teardown { Live::RECURSOS.delete("clientes_teste") }

  test "só quem está presente recebe; o registro vai no formato da tela; o que a pessoa não vê vai em removidos" do
    cliente = Customer.create!(tenant: tenants(:alfa), document: "52998224725", name: "Maria Souza")
    presente = users(:joana)
    Live::Presence.enter(presente)
    ausentes = Live.tenant_user_ids(cliente.tenant_id) - [ presente.id ]

    assert_broadcasts(LiveChannel.broadcasting_for(presente), 1) do
      LiveBroadcastJob.perform_now("clientes_teste", [ cliente.id, -1 ], cliente.tenant_id)
    end
    mensagem = broadcasts(LiveChannel.broadcasting_for(presente)).last.then { |dados| JSON.parse(dados) }
    assert_equal "atualizar", mensagem["acao"]
    assert_equal [ cliente.id ], mensagem["registros"].map { |registro| registro["id"] }
    assert_equal [ -1 ], mensagem["removidos"]
    ausentes.each { |id| assert_empty broadcasts(LiveChannel.broadcasting_for(User.find(id))) }
  end

  test "acima do limite, a mensagem só pede para recarregar" do
    presente = users(:joana)
    Live::Presence.enter(presente)

    LiveBroadcastJob.perform_now("clientes_teste", (1..(Live::LIMITE + 1)).to_a, tenants(:alfa).id)

    assert_equal({ "recurso" => "clientes_teste", "acao" => "recarregar" }, JSON.parse(broadcasts(LiveChannel.broadcasting_for(presente)).last))
  end
end
