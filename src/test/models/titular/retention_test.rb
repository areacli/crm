require "test_helper"

# Guarda automática (07, R136 a R139, R137a, R138a): fim da última relação, previsão, tarefa diária por credor e retenção.
class RetentionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @gestor = users(:joana)
  end

  def years_ago(years, days = 0) = Date.current - years.years - days.days

  # Faz o lote falhar (erro do banco) quando `condition` aceita os argumentos; fora disso chama o método de verdade.
  def failing_batches(condition)
    original = Titular::Anonymizer.method(:in_batch)
    Titular::Anonymizer.singleton_class.define_method(:in_batch) { |tenant_id, ids| condition.call(tenant_id, ids) ? raise(ActiveRecord::StatementInvalid, "falha simulada") : original.call(tenant_id, ids) }
    yield
  ensure
    Titular::Anonymizer.singleton_class.define_method(:in_batch, original)
  end

  def due_ids(tenant = @alfa, within: 0) = Titular::Retention.due([ tenant.id ], within: within).pluck(:id)

  test "R137 (critério de aceite): fim da relação há 5 anos e 1 dia, sem retenção, é anonimizado pela tarefa, que registra 1" do
    jose = make_full_customer(@alfa, ended_on: years_ago(5, 1), document: PaymentsHelper::JOAO, name: "José")
    recente = make_full_customer(@alfa, ended_on: years_ago(5, -1), name: "Recente")

    run = Titular::RetentionRun.new(@alfa).call

    assert jose.reload.anonymized?
    assert_not recente.reload.anonymized?
    assert_equal [ "succeeded", 1, 0, @alfa ], [ run.status, run.processed, run.failed, run.tenant ]
    assert run.finished_at
  end

  test "R137 (exemplo): fim da relação em 15/10/2021 com prazo de 5 anos vence em 15/10/2026" do
    customer = make_full_customer(@alfa, ended_on: Date.new(2021, 10, 15))

    assert_not_includes due_ids, customer.id unless Date.current >= Date.new(2026, 10, 15)
    assert_includes Titular::Retention.due([ @alfa.id ], today: Date.new(2026, 10, 15)).pluck(:id), customer.id
    assert_not_includes Titular::Retention.due([ @alfa.id ], today: Date.new(2026, 10, 14)).pluck(:id), customer.id
  end

  test "R136: o prazo é do credor; mudar vale para a próxima execução" do
    customer = make_full_customer(@alfa, ended_on: years_ago(5, 10))
    assert_includes due_ids, customer.id

    @alfa.setting.update!(retention_years: 6)
    assert_not_includes due_ids, customer.id
    assert_raises(ActiveRecord::RecordInvalid) { @alfa.setting.update!(retention_years: 0) }
  end

  test "fim da última relação: pagamento, estorno, crédito e título retirado sem saldo contam; sem nenhum fato vale a entrada do cliente" do
    customer = make_full_customer(@alfa, ended_on: years_ago(8))
    assert_includes due_ids, customer.id

    PaymentReversal.create!(tenant: @alfa, channel: customer.payment.channel, payment: customer.payment, identifier: "E1", reversed_on: Date.current - 10, amount_cents: 1)
    assert_not_includes due_ids, customer.id, "estorno recente recomeça o prazo"

    semfato = Customer.create!(tenant: @alfa, document: PaymentsHelper::JOAO, name: "Sem fato")
    semfato.update_columns(created_at: years_ago(6).to_time)
    assert_includes due_ids, semfato.id
  end

  test "R139: título novo (relação em aberto) tira da previsão; o prazo recomeça quando a relação fecha" do
    customer = make_full_customer(@alfa, ended_on: years_ago(5, 3))
    assert_includes due_ids, customer.id

    novo = make_bill(@alfa, document: PaymentsHelper::MARIA, number: "NF-NOVO", contract_code: "CT-7")
    assert_not_includes due_ids(within: 30), customer.id

    novo.update!(status: :paid, paid_cents: novo.amount_cents, paid_on: Date.current)
    assert_not_includes due_ids(within: 30), customer.id
  end

  test "R138: a previsão dos próximos 30 dias traz quem vence nessa janela, com a data" do
    soon = make_full_customer(@alfa, ended_on: years_ago(5, -10), name: "Em breve")
    far = make_full_customer(@alfa, ended_on: years_ago(5, -40), document: PaymentsHelper::JOAO, name: "Longe")

    ids = due_ids(within: 30)

    assert_includes ids, soon.id
    assert_not_includes ids, far.id
    row = Titular::Retention.due([ @alfa.id ], within: 30).find(soon.id)
    assert_equal (years_ago(5, -10) + 5.years), row.attributes["due_on"]
  end

  test "R138 (critério de aceite): reter tira da previsão e a tarefa não anonimiza; desfeita a retenção, volta" do
    jose = make_full_customer(@alfa, ended_on: years_ago(5, 1))
    Titular::Retainer.new(@gestor).retain(jose, "ação judicial em curso")

    assert_not_includes due_ids, jose.id
    assert_equal 0, Titular::RetentionRun.new(@alfa).call.processed
    assert_not jose.reload.anonymized?
    assert_equal [ "retained", "ação judicial em curso" ], Change.where(subject_type: "customer", subject_id: jose.id, event: "retained").pick(:event, :note)

    Titular::Retainer.new(@gestor).release(jose, "processo encerrado")
    assert_includes due_ids, jose.id
  end

  test "R138: reter anonimizado, reter quem já está retido e desfazer quem não está são recusados; o motivo é obrigatório" do
    jose = make_full_customer(@alfa, ended_on: years_ago(5, 1))
    retainer = Titular::Retainer.new(@gestor)
    assert_raises(Titular::Refused) { retainer.retain(jose, "") }
    assert_raises(Titular::Refused) { retainer.release(jose, "x") }
    retainer.retain(jose, "processo")
    assert_raises(Titular::Refused) { retainer.retain(jose, "outra vez") }
    retainer.release(jose, "fim")
    Titular::Anonymizer.in_batch(@alfa.id, [ jose.id ])
    assert_raises(Titular::Refused) { retainer.retain(jose.reload, "tarde") }
  end

  test "R138a (critério de aceite): contrato com Ana retida e Pedro livre, último pagamento há 5 anos e 1 dia: só Pedro é anonimizado" do
    ana = make_full_customer(@alfa, ended_on: years_ago(5, 1), name: "Ana", code: "CT-7")
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro", contract_code: "CT-7")
    Bill.where(customer_id: pedro.id).update_all(status: "paid", paid_cents: 100_000, paid_on: years_ago(9))
    ContractCustomer.find_or_create_by!(contract: ana.contracts.first, customer: pedro)
    Titular::Retainer.new(@gestor).retain(ana, "processo")

    Titular::RetentionRun.new(@alfa).call

    assert pedro.reload.anonymized?
    assert_not ana.reload.anonymized?
  end

  test "R138a: um fato recente de qualquer cliente do contrato recomeça o prazo de todos" do
    ana = make_full_customer(@alfa, ended_on: years_ago(9), name: "Ana", code: "CT-7")
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro", contract_code: "CT-7")
    Bill.where(customer_id: pedro.id).update_all(status: "paid", paid_cents: 100_000, paid_on: Date.current - 20)
    ContractCustomer.find_or_create_by!(contract: ana.contracts.first, customer: pedro)

    assert_empty due_ids
  end

  test "R137a (critério de aceite): a Alfa com 5 anos e a Beta com 6; cada uma segue o próprio prazo e a falha de uma não impede a outra" do
    @beta.setting.update!(retention_years: 6)
    alfa_customer = make_full_customer(@alfa, ended_on: years_ago(5, 5))
    beta_customer = make_full_customer(@beta, ended_on: years_ago(5, 5))

    alfa_run = Titular::RetentionRun.new(@alfa).call
    assert alfa_customer.reload.anonymized?
    assert_not beta_customer.reload.anonymized?
    assert_equal @alfa, alfa_run.tenant

    @beta.setting.update!(retention_years: 5)
    failing_batches(->(*) { true }) do
      failed = Titular::RetentionRun.new(@beta).call
      assert_equal [ "failed", 1, "StatementInvalid" ], [ failed.status, failed.failed, failed.error_kind ]
    end
    assert_not beta_customer.reload.anonymized?
    other = make_full_customer(@alfa, ended_on: years_ago(5, 5), document: PaymentsHelper::JOAO, name: "Outro")
    assert Titular::RetentionRun.new(@alfa).call.processed == 1 && other.reload.anonymized?
  end

  test "exceção: com importação em andamento a execução é adiada e registrada" do
    make_full_customer(@alfa, ended_on: years_ago(6))
    Import.create!(tenant: @alfa, user: @gestor, mode: :incremental, status: :confirming, original_name: "x.csv")

    run = Titular::RetentionRun.new(@alfa).call

    assert_equal [ "skipped", 0 ], [ run.status, run.processed ]
  end

  test "exceção: falha num cliente do lote não impede os outros (refaz um a um)" do
    ruim = make_full_customer(@alfa, ended_on: years_ago(6), name: "Ruim")
    bom = make_full_customer(@alfa, ended_on: years_ago(6), document: PaymentsHelper::JOAO, name: "Bom")
    failing_batches(->(_tenant_id, ids) { ids.include?(ruim.id) }) do
      run = Titular::RetentionRun.new(@alfa).call
      assert_equal [ 1, 1 ], [ run.processed, run.failed ]
    end
    assert_equal [ false, true ], [ ruim.reload.anonymized?, bom.reload.anonymized? ]
  end

  test "pagamento pendente com o documento do cliente mantém a relação em aberto" do
    customer = make_full_customer(@alfa, ended_on: years_ago(6))
    Payment.create!(tenant: @alfa, channel: customer.payment.channel, identifier: "P", document: customer.document, bill_number: "X", paid_on: Date.current, amount_cents: 10,
                    payment_method: "pix", status: "pending")

    assert_not_includes due_ids, customer.id
  end

  test "R137: o dispatch enfileira um job por credor ativo e o agendamento está em config/schedule.yml" do
    @beta.update!(active: false)

    assert_enqueued_with(job: RetentionJob, args: [ @alfa ]) { RetentionDispatchJob.perform_now }
    assert_enqueued_jobs 1, only: RetentionJob

    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    assert_equal [ "0 3 * * *", "RetentionDispatchJob" ], schedule["data_retention"].values_at("cron", "class")
  end

  test "caso de exceção: a execução do Sidekiq roda o job e registra a execução do credor" do
    make_full_customer(@alfa, ended_on: years_ago(6))
    perform_enqueued_jobs { RetentionJob.perform_later(@alfa) }

    assert_equal 1, TaskRun.where(tenant: @alfa, name: "data_retention", status: "succeeded").count
  end

  test "V10: a previsão de um credor não traz clientes de outro" do
    make_full_customer(@beta, ended_on: years_ago(6))

    assert_empty due_ids(@alfa)
    assert_equal 1, due_ids(@beta).size
  end
end
