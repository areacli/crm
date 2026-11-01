require "test_helper"

# "Está pra mim?" no banco (14, R313, R314; decisão 0024): com o papel da operação, cada tabela de carteira só devolve o que está pra ela, por
# qualquer caminho (consulta, associação, SQL escrito à mão); a equipe do credor vê tudo; nada depende de a tela lembrar.
class Operations::ReachTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    @caio = make_operation_user(@operation, @alfa)
    @ana = make_customer(@alfa, document: FakeData.cpf(101), name: "Ana Lima", contract_code: "C-7")
    @c7 = Contract.find_by!(tenant: @alfa, code: "C-7")
    @old = @c7.bills.first
    @old.update!(due_date: Date.current - 40)
    @recent = Bill.create!(tenant: @alfa, contract: @c7, customer: @ana, number: "C-7/2", due_date: Date.current - 1, amount_cents: 50_000)
    @future = Bill.create!(tenant: @alfa, contract: @c7, customer: @ana, number: "C-7/3", due_date: Date.current + 30, amount_cents: 50_000)
    @c12 = Contract.create!(tenant: @alfa, code: "C-12")
    ContractCustomer.create!(contract: @c12, customer: @ana)
    @c12_bill = Bill.create!(tenant: @alfa, contract: @c12, customer: @ana, number: "C-12/1", due_date: Date.current - 60, amount_cents: 70_000)
    @bia = make_customer(@alfa, document: FakeData.cpf(102), name: "Bia Rocha", contract_code: "C-20")
  end

  def distribute(target, exposure: "overdue", starts_on: Date.current - 1, ends_on: nil)
    key = target.is_a?(Customer) ? :customer : :contract
    Distribution.create!(tenant: @alfa, operation: @operation, key => target, exposure: exposure, starts_on: starts_on, ends_on: ends_on)
    Operations::ReachBuilder.new(@alfa).rebuild
  end

  def as(user, &) = Operations::Context.for_user(user, &)

  test "R313: contrato distribuído, vencidas há mais de 3 dias úteis; o outro contrato e a outra cliente não existem pra operação" do
    distribute(@c7)
    as(@caio) do
      assert_equal [ @c7.id ], Contract.where(tenant: @alfa).pluck(:id)
      assert_equal [ @ana.id ], Customer.where(tenant: @alfa).pluck(:id)
      assert_equal [ @old.id ], Bill.where(tenant: @alfa).pluck(:id), "a fatura de ontem e a futura não estão na exposição"
      assert_equal [ @c7.id ], @ana.contracts.pluck(:id), "a associação também passa pelo banco"
      assert_nil Customer.find_by(id: @bia.id)
      assert_equal 1, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM bills WHERE tenant_id = #{@alfa.id}")
    end
    as(users(:joana)) { assert_equal 5, Bill.where(tenant: @alfa).count }
  end

  test "R313: exposição vencidas e a vencer; cliente distribuída leva os contratos dela, inclusive o que chegar depois" do
    distribute(@ana, exposure: "all")
    as(@caio) { assert_equal [ @c12.id, @c7.id ].sort, Contract.where(tenant: @alfa).pluck(:id).sort }
    novo = Contract.create!(tenant: @alfa, code: "C-30")
    ContractCustomer.create!(contract: novo, customer: @ana)
    Operations::ReachBuilder.new(@alfa).rebuild
    as(@caio) do
      assert_includes Contract.where(tenant: @alfa).pluck(:id), novo.id
      assert_includes Bill.where(tenant: @alfa).pluck(:id), @future.id
    end
  end

  test "R311: distribuição agendada ou encerrada não alcança; credenciamento suspenso também não" do
    distribute(@c7, starts_on: Date.current + 2)
    as(@caio) { assert_empty Contract.where(tenant: @alfa).pluck(:id) }
    Distribution.update_all(starts_on: Date.current - 1)
    Operations::ReachBuilder.new(@alfa).rebuild
    as(@caio) { assert_equal [ @c7.id ], Contract.where(tenant: @alfa).pluck(:id) }
    Operations::Accreditor.new(users(:joana)).change_status(Accreditation.find_by(tenant: @alfa, operation: @operation), "suspended", "pendência")
    as(@caio) { assert_empty Contract.where(tenant: @alfa).pluck(:id) }
  end

  test "OP-11: a fatura da promessa da operação continua pra ela depois do fim da distribuição" do
    distribute(@c7)
    promise = as(@caio) { register_promise(@ana, [ @old ], user: @caio) }
    assert_equal @operation.id, promise.operation_id, "a origem vem do contexto"
    assert_includes %w[pending open], promise.state
    Distributions::Closer.new(users(:joana)).close(Distribution.last, reason: "performance")
    as(@caio) do
      assert_equal [ @old.id ], Bill.where(tenant: @alfa).pluck(:id)
      assert_equal [ promise.id ], PaymentPromise.where(tenant: @alfa).pluck(:id)
    end
  end

  test "sem papel declarado, o sistema vê tudo; o bloco sistema abre a visão dentro da requisição da operação" do
    distribute(@c7)
    as(@caio) do
      assert_equal 1, Customer.where(tenant: @alfa).count
      assert_equal 2, Operations::Context.system { Customer.where(tenant: @alfa).count }
      assert_equal 1, Customer.where(tenant: @alfa).count
    end
  end
end
