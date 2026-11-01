require "test_helper"

# Papel de entrada da aplicação (decisão 0024): sem superusuário, ele lê as tabelas sem política e nada da carteira até declarar um papel
# (falha fechada); como `crm_team` vê tudo; como `crm_operation`, só o que está pra a operação declarada. A conexão é aberta à parte, como
# a aplicação em produção abriria.
class AppRoleTest < ActiveSupport::TestCase
  ROLE = "crm_app_teste".freeze
  PASSWORD = "senha-do-papel-de-teste".freeze

  setup do
    # Por uma conexão à parte, do dono: a transação do teste não guardaria o papel para a entrada.
    owner = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(ActiveRecord::Base.connection_db_config.configuration_hash)
    Operations::Rls.create_login!(ROLE, PASSWORD, owner)
  rescue ActiveRecord::StatementInvalid => error
    # Os bancos dos testes paralelos dividem os papéis do servidor: dois criando o mesmo papel ao mesmo tempo, um repete.
    raise unless error.message.include?("already exists") || error.message.include?("concurrently")

    retry
  ensure
    owner&.disconnect!
  end

  def connect
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(host: config[:host], dbname: config[:database], user: ROLE, password: PASSWORD)
  end

  def count(connection, table) = connection.exec("select count(*) from #{table}").getvalue(0, 0).to_i

  test "sem papel declarado não lê a carteira, mas lê usuários e sessões" do
    connection = connect
    assert_not connection.exec("select rolsuper or rolbypassrls from pg_roles where rolname = current_user").getvalue(0, 0) == "t"
    assert_equal 0, count(connection, "customers")
    assert_equal 0, count(connection, "bills")
    assert_operator count(connection, "users"), :>, 0
  ensure
    connection&.close
  end

  test "como equipe lê e grava; como operação, a política recorta; o dono não se assume" do
    connection = connect
    # A conexão à parte não vê a transação do teste: grava e confere dentro da sua, desfeita no fim.
    connection.exec("begin")
    connection.exec("set role crm_team")
    connection.exec_params("insert into customers (tenant_id, document, name, created_at, updated_at) values ($1, $2, 'Ana Papel', now(), now())",
                           [ tenants(:alfa).id, FakeData.cpf(611) ])
    assert_equal 1, count(connection, "customers")
    connection.exec("set role crm_operation")
    connection.exec("select set_config('crm.operation', '0', true)")
    assert_equal 0, count(connection, "customers")
    connection.exec("rollback")
    assert_raises(PG::InsufficientPrivilege) { connection.exec("set role crm") }
  ensure
    connection&.close
  end
end
