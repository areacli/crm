require "test_helper"

# Controladores sem usuário do back office (decisão 0024): em produção a conexão entra como o papel sem privilégios, que não lê a carteira
# sem declarar um papel. O teste troca a conexão para um papel desses antes da requisição: a página pública de pagamento só abre porque o
# controlador declara o papel do sistema (sem isso, respondia 404 para todo link, como aconteceu na publicação de 31/10/2026).
class SystemDbRoleTest < ActionDispatch::IntegrationTest
  ROLE = "crm_app_teste".freeze

  setup do
    owner = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(ActiveRecord::Base.connection_db_config.configuration_hash)
    Operations::Rls.create_login!(ROLE, "senha-do-papel-de-teste", owner)
  rescue ActiveRecord::StatementInvalid => error
    raise unless error.message.include?("already exists") || error.message.include?("concurrently")

    retry
  ensure
    owner&.disconnect!
  end

  teardown { ActiveRecord::Base.connection.execute("RESET ROLE") }

  def as_entry_role = ActiveRecord::Base.connection.execute("SET ROLE #{ROLE}")

  test "a página pública de pagamento abre com o papel de entrada" do
    checkout = make_checkout
    as_entry_role
    assert_equal 0, Customer.count, "o papel de entrada não deveria ler a carteira sem declarar papel"

    get checkout_path(checkout)
    assert_response :success
  end
end
