require "test_helper"

# Webhooks e conciliação (12, parte D): regras que não podem se perder com o tempo. O aviso nunca atualiza sem consultar; o aviso é idempotente; só o
# adaptador sabe autenticar; V10; nada de dado de cartão nem do pagador no aviso.
class WebhooksArchitectureTest < ActiveSupport::TestCase
  ROOT = Rails.root

  def source(path) = File.read(ROOT.join(path))

  test "o controlador do webhook só lê, confere e guarda: não chama o fornecedor, não toca instrumento nem pagamento" do
    text = source("app/controllers/webhooks/payment_accounts_controller.rb").lines.reject { |line| line.strip.start_with?("#") }.join
    assert_no_match(/PaymentInstrument|Payment\.|ExternalPayment|InstrumentSync|Processor|fetch_|expand_notification|\.adapter\.(?!parse_notification)/, text)
    assert_match(/parse_notification/, text)
    assert_match(/ProcessPaymentEventJob\.perform_later/, text)
  end

  test "o estado do instrumento só muda depois de uma consulta ao fornecedor: InstrumentSync consulta antes de aplicar, e é o único que marca pago" do
    sync = source("app/models/payments/instrument_sync.rb")
    assert_operator sync.index("consult(instrument)"), :<, sync.index("apply(instrument, issued, notification)")
    writers = Dir[ROOT.join("app/**/*.rb")].select { |file| File.read(file).match?(/state:\s*"paid"|update!\(state: "paid"|state_paid!|paid!\b/) }.map { |file| file.delete_prefix("#{ROOT}/") }
    allowed = %w[app/models/payments/instrument_sync.rb app/models/payments/card_charger.rb app/models/payment_checkout.rb app/models/payments/checkouts.rb]
    assert_empty writers - allowed, "só o InstrumentSync marca instrumento pago (o CardCharger grava `paid` quando o próprio fornecedor responde pago na cobrança)"
  end

  test "o job do aviso e a conciliação passam por InstrumentSync, na fila webhooks" do
    assert_equal "webhooks", ProcessPaymentEventJob.new.queue_name
    assert_equal "webhooks", ReconcileInstrumentJob.new.queue_name
    assert_match(/InstrumentSync/, source("app/models/payments/event_processor.rb"))
    assert_match(/InstrumentSync/, source("app/jobs/reconcile_instrument_job.rb"))
    assert_includes YAML.load_file(ROOT.join("config/sidekiq.yml"))[:queues], "webhooks"
  end

  test "a idempotência é do banco: índice único por conta e identificador do evento" do
    index = ActiveRecord::Base.connection.indexes(:payment_events).find { |candidate| candidate.columns == %w[account_id event_id] }
    assert_predicate index, :unique
  end

  test "a autenticação do aviso é do adaptador: o controlador não conhece segredo, assinatura nem cabeçalho de fornecedor" do
    text = source("app/controllers/webhooks/payment_accounts_controller.rb").lines.reject { |line| line.strip.start_with?("#") }.join
    assert_no_match(/OpenSSL|X-Signature|webhook_secret|secure_compare/, text)
  end

  test "o aviso guarda o mínimo: sem coluna de pagador, de cartão ou de corpo bruto" do
    columns = PaymentEvent.column_names
    assert_empty columns & %w[payer_name payer_document payer_address body payload raw number cvv holder pan]
    assert_empty PaymentEvent.encrypted_attributes.to_a
  end

  test "dado de cartão nunca entra no aviso nem nas rotas de webhook: os nomes filtrados do log valem também para o corpo" do
    filters = Rails.application.config.filter_parameters.map(&:to_s)
    %w[number cvv].each { |name| assert(filters.any? { |filter| filter.include?(name) }, "#{name} fora do filtro") }
    routes = Rails.application.routes.routes.select { |route| route.path.spec.to_s.start_with?("/webhooks/") }
    assert_equal %w[POST], routes.map(&:verb).uniq
  end

  test "as rotas de webhook respondem sem sessão e o aviso não herda do back office" do
    assert_not_includes Webhooks::PaymentAccountsController.ancestors, Authentication
    assert_operator Webhooks::PaymentAccountsController, :<, ActionController::API
  end

  test "isolamento por credor: toda busca de instrumento do aviso é pela conta do aviso" do
    text = source("app/models/payments/event_processor.rb")
    assert_match(/where\(account_id: account\.id\)/, text)
    assert_no_match(/PaymentInstrument\.find_by|PaymentInstrument\.find\(/, text)
  end

  test "o pagamento do instrumento passa por ExternalPayment, o mesmo caminho do webhook genérico e da planilha" do
    assert_match(/ExternalPayment/, source("app/models/payments/instrument_sync.rb"))
    assert_match(/ExternalPayment/, source("app/models/payments/webhook_processor.rb"))
    assert_match(/Processor\.new\.run/, source("app/models/payments/external_payment.rb"))
    assert_match(/ReversalProcessor\.new\.run/, source("app/models/payments/external_payment.rb"))
  end

  test "não há polling na conciliação: nenhuma tela nem canal consulta o fornecedor" do
    views = Dir[ROOT.join("app/{views,javascript}/**/*")].reject { |file| File.directory?(file) }
    views.each { |file| assert_no_match(/setInterval|hx-trigger="every/, File.read(file), file) }
  end
end
