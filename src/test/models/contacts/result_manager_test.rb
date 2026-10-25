require "test_helper"

# Lista de resultados do credor (04): R66, R67, R68 e R77.
class Contacts::ResultManagerTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @manager = Contacts::ResultManager.new(users(:joana))
  end

  test "R68: o credor novo recebe os 11 resultados da lista inicial, com tipo e regra de retorno" do
    tenant = Tenant.provision!("Gama")
    results = tenant.contact_results.ordered.to_a

    assert_equal 11, results.size
    assert_equal [ "Pediu para retornar depois", "spoke_with_customer", "required" ], results.first.values_at(:name, :kind, :return_rule)
    assert_equal [ "Número ou endereço inexistente", "no_contact", "not_allowed" ], results.last.values_at(:name, :kind, :return_rule)
    assert_equal 3, results.map(&:kind).uniq.size
    assert results.all?(&:active?)
  end

  test "R66: o resultado novo entra no fim e o criador fica no histórico (R77)" do
    result = @manager.create(tenant: @alfa, name: "Pediu boleto por e-mail", kind: "spoke_with_customer", return_rule: "allowed")

    assert_equal @alfa.contact_results.maximum(:position), result.position
    assert_equal result, @alfa.contact_results.ordered.last
    change = Change.where(subject_type: "contact_result", subject_id: result.id).sole
    assert_equal [ "created", "Pediu boleto por e-mail", users(:joana).id, @alfa.id ], [ change.event, change.after, change.user_id, change.tenant_id ]
  end

  test "R66: o nome é único no credor sem diferença de maiúsculas e acentos; o mesmo nome vale em outro credor" do
    error = assert_raises(ActiveRecord::RecordInvalid) { @manager.create(tenant: @alfa, name: "  NAO   atendeu ", kind: "no_contact", return_rule: "allowed") }
    assert_includes error.record.errors.full_messages.to_sentence, "já existe um resultado com esse nome neste credor"

    novo = @manager.create(tenant: @alfa, name: "Aguardando o banco", kind: "no_contact", return_rule: "allowed")
    assert_equal novo.name, "Aguardando o banco"
    assert @manager.create(tenant: @beta, name: "Aguardando o banco", kind: "no_contact", return_rule: "not_allowed")
  end

  test "R66: o gestor de um credor edita só a lista dele, e a lista do outro não muda" do
    @manager.create(tenant: @alfa, name: "Só da Alfa", kind: "no_contact", return_rule: "allowed")
    assert_not @beta.contact_results.exists?(name: "Só da Alfa")

    result = result_of(@alfa, :voicemail)
    @manager.update(result, name: "Caixa postal cheia", return_rule: "not_allowed")
    assert_equal "Caixa postal", result_of(@beta, :voicemail).name
  end

  test "R66: renomear e mudar a regra de retorno ficam registrados, e o tipo não é alterado pelo gerenciador" do
    result = result_of(@alfa, :voicemail)

    @manager.update(result, name: "Caixa postal cheia", return_rule: "not_allowed")

    result.reload
    assert_equal [ "Caixa postal cheia", "not_allowed", "no_contact" ], result.values_at(:name, :return_rule, :kind)
    events = Change.where(subject_type: "contact_result", subject_id: result.id).order(:id)
    assert_equal [ [ "renamed", "Caixa postal", "Caixa postal cheia" ], [ "return_rule_changed", "allowed", "not_allowed" ] ], events.map { |e| [ e.event, e.before, e.after ] }
  end

  test "R67: o resultado usado não é apagado, só desativado; some da escolha e continua nos acionamentos antigos" do
    customer = make_customer(@alfa)
    result = result_of(@alfa, :voicemail)
    attempt = record_attempt(customer, users(:joana), result: result)

    assert_not result.destroy
    assert ContactResult.exists?(result.id)

    @manager.set_active(result, false)
    assert_not_includes Contacts::Form.new(customer).results, result
    assert_equal "Caixa postal", attempt.reload.result.name
    assert_includes Contacts::Form.new(make_customer(tenants(:beta))).results.map(&:name), "Caixa postal"
    assert_equal "deactivated", Change.where(subject_type: "contact_result", subject_id: result.id).last.event

    @manager.set_active(result, true)
    assert_includes Contacts::Form.new(customer).results, result
    assert_equal "reactivated", Change.where(subject_type: "contact_result", subject_id: result.id).last.event
  end

  test "revisão 2: subir e descer trocam a posição com o vizinho e ficam registrados; nos extremos não fazem nada" do
    list = -> { @alfa.contact_results.ordered.pluck(:name) }
    first, second = list.call.first(2)
    result = @alfa.contact_results.find_by!(name: second)

    @manager.move(result, "up")
    assert_equal [ second, first ], list.call.first(2)
    @manager.move(result, "up")
    assert_equal [ second, first ], list.call.first(2)
    @manager.move(result, "down")
    assert_equal [ first, second ], list.call.first(2)
    assert_equal %w[moved moved], Change.where(subject_type: "contact_result", subject_id: result.id, event: "moved").pluck(:event)

    last = @alfa.contact_results.ordered.last
    before = list.call
    @manager.move(last, "down")
    assert_equal before, list.call
  end
end
