require "test_helper"

# A carga da demonstração (CRM_DEMO=1) com uma carteira menor: cada cenário que a especificação e o o documento da demonstração do projeto prometem existe, nada chama a internet e a
# recriação apaga e recria sem perder os usuários públicos.
class DemoDatasetTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @previous = Rails.configuration.x.demo.enabled
    @customers = Rails.configuration.x.demo.customers
    Rails.configuration.x.demo.enabled = true
    Rails.configuration.x.demo.customers = 800
    Indexes.client = nil
  end

  teardown do
    Rails.configuration.x.demo.enabled = @previous
    Rails.configuration.x.demo.customers = @customers
    # O teste não é transacional (a recriação trunca tabelas): devolve o banco ao que as fixtures esperam.
    Demo::Reset.new.wipe
    Session.delete_all
    User.where("email_address like ?", "%@#{Demo.domain}").delete_all
  end

  def reset_without_network
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*| raise "chamada externa" }
    Demo::Reset.new.call
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  # A carga leva ~25 s: uma só, conferida por partes (cada parte é um cenário que a especificação ou o o documento da demonstração do projeto promete).
  test "a carga da demonstração tem cada cenário prometido e não chama a internet" do
    reset_without_network
    # --- Dois credores, usuários públicos com perfis diferentes e o isolamento entre os credores
    alpha = Tenant.find_by!(name: "Escola Alfa")
    beta = Tenant.find_by!(name: "Clínica Beta")
    manager = User.find_by!(email_address: Demo.email("gestor"))
    operator = User.find_by!(email_address: Demo.email("operador"))

    assert manager.authenticate(Demo.password("gestor"))
    assert operator.authenticate(Demo.password("operador"))
    assert_equal "Gestor demonstração", manager.memberships.find_by!(tenant: alpha).profile.name
    assert_equal "Operador", manager.memberships.find_by!(tenant: beta).profile.name
    assert_equal [ alpha.id ], operator.memberships.pluck(:tenant_id)
    assert_not manager.permitted?("manage_users", alpha), "usuários e perfis ficam fechados (permissoes.md)"
    assert_not manager.permitted?("manage_profiles", alpha)
    assert manager.permitted?("change_financial_policies", alpha)
    assert_equal [ alpha.id, beta.id ].sort, manager.tenant_ids_with("view_portfolio").sort
    assert_equal [ alpha.id ], operator.tenant_ids_with("view_portfolio")
    assert_equal 0, Customer.where(tenant_id: beta.id).where(id: Customer.where(tenant_id: alpha.id).select(:id)).count
    assert_operator Customer.where(tenant_id: beta.id).count, :>, 20
    assert_operator Customer.where(tenant_id: alpha.id).count, :>=, 800

    # --- Carteira: faixas de atraso, a vencer, desde 2020, pagamentos, estornos e divergências
    bills = Bill.where(tenant_id: alpha.id, kind: "common")

    assert_operator bills.minimum(:due_date), :<=, Date.new(2021, 1, 1)
    assert_operator bills.where("due_date > ?", Date.current).count, :>, 0, "a vencer"
    [ 1..30, 31..60, 61..90, 91..180, 181..360 ].each do |range|
      assert_operator bills.where(status: "active", paid_cents: 0).where("current_date - due_date between ? and ?", range.first, range.last).count, :>, 0, "faixa #{range}"
    end
    assert_operator bills.where(status: "active", paid_cents: 0).where("current_date - due_date > 360").count, :>, 0
    assert_operator bills.where(status: "paid").count, :>, 0
    assert_operator bills.where("paid_cents > 0 and status = 'active'").count, :>, 0, "pagamento parcial"
    assert_operator Credit.where(tenant_id: alpha.id).count, :>, 0, "crédito"
    assert_operator Payment.where(tenant_id: alpha.id, status: "applied").count, :>, 100
    assert_operator PaymentReversal.where(tenant_id: alpha.id).count, :>, 0
    assert_operator ValueDiscrepancy.where(tenant_id: alpha.id).count, :>, 0
    assert_operator ContactAttempt.where(tenant_id: alpha.id).count, :>=, 30_000
    assert_equal ContactResult.where(tenant_id: alpha.id).count, ContactAttempt.where(tenant_id: alpha.id).distinct.count(:result_id)
    assert_operator CustomerContact.where(tenant_id: alpha.id, status: "invalid").count, :>, 0
    assert_operator CustomerContact.where(tenant_id: alpha.id, status: "do_not_disturb").count, :>, 0
    assert_operator Segment.where(tenant_id: alpha.id).count, :>=, 4
    assert_operator Contract.where(tenant_id: alpha.id).where.not(segment_id: nil).distinct.count(:segment_id), :>=, 3
    assert_operator IndexRate.count, :>, 300
    assert_operator IndexAdjustment.where(tenant_id: alpha.id).count, :>, 0
    assert_operator BillValuation.where(tenant_id: alpha.id).count, :>, 100
    assert Import.where(tenant_id: alpha.id, status: "checked").exists?, "uma importação à espera de confirmação"
    assert_operator ImportRejection.where(import_id: Import.where(tenant_id: alpha.id, status: "checked").select(:id)).count, :>=, 3

    # --- Promessas nos oito estados e acordos nos estados principais, incluindo quebrado, efetivado e revertido
    alpha = Tenant.find_by!(name: "Escola Alfa")

    assert_equal PaymentPromise::STATES.sort, PaymentPromise.where(tenant_id: alpha.id).distinct.pluck(:state).sort
    states = Agreement.where(tenant_id: alpha.id).distinct.pluck(:state)
    %w[pending approved refused canceled expired not_approved awaiting_effectuation active_on_time settled broken].each { |state| assert_includes states, state }
    assert(Agreement.where(tenant_id: alpha.id).where.not(reversing_since: nil).exists?, "uma reversão aberta")
    assert(Agreement.where(tenant_id: alpha.id, state: "canceled").where.not(reverted_at: nil).exists?, "uma reversão concluída")

    # --- Direitos do titular, instrumentos do fornecedor falso e o link de pagamento de exemplo
    alpha = Tenant.find_by!(name: "Escola Alfa")

    anonymized = Customer.where(tenant_id: alpha.id).where.not(anonymized_at: nil)
    assert_equal 1, anonymized.count
    assert_match(/\ACliente anonimizado nº /, anonymized.first.name)
    assert Change.where(tenant_id: alpha.id, event: "data_exported").exists?
    assert Customer.where(tenant_id: alpha.id).where.not(retained_at: nil).exists?

    assert_equal [ "fake" ], PaymentAccount.where(tenant_id: alpha.id).distinct.pluck(:provider)
    assert_equal %w[boleto card pix], PaymentAccount.where(tenant_id: alpha.id).pluck(:modality).sort
    assert_equal [ "fake" ], PaymentInstrument.distinct.pluck(:provider)
    assert PaymentInstrument.where(kind: "boleto", state: "active").exists?
    assert PaymentInstrument.where(kind: "pix", state: "active").exists?
    assert PaymentInstrument.where(state: "failed").exists?, "uma emissão que falhou"
    assert_predicate PaymentInstrument.where(kind: "pix", state: "active").first.pix_qr_sha256, :present?, "o QR Code do Pix foi gerado daqui"
    instrument = PaymentInstrument.where(kind: "boleto", state: "active").first
    assert_predicate instrument.boleto_pdf_sha256, :present?
    checkout = PaymentCheckout.find_by!(token: Demo::Dataset::InstrumentSteps::CHECKOUT_TOKEN)
    assert_equal %w[boleto card pix], checkout.modalities.sort
    assert checkout.available?
  end

  test "recriar apaga e recria tudo e mantém os usuários públicos e as sessões" do
    reset_without_network
    manager = User.find_by!(email_address: Demo.email("gestor"))
    session = manager.sessions.create!
    stale = Tenant.create!(name: "Credor do visitante")
    waiting = Import.find_by!(status: "checked")
    assert File.exist?(waiting.file_path), "a importação à espera guarda o arquivo"
    attachments = ActiveStorage::Blob.count

    run = Demo::Reset.new.call
    assert_predicate run, :succeeded?
    assert_not Tenant.exists?(stale.id)
    assert_equal 2, Tenant.count
    assert_equal manager.id, User.find_by!(email_address: Demo.email("gestor")).id
    assert Session.exists?(session.id), "as sessões abertas continuam valendo"
    assert_not File.exist?(waiting.file_path), "o arquivo da recriação anterior saiu do disco"
    assert_operator ActiveStorage::Blob.count, :>=, 1
    assert_operator attachments, :>=, 1
    assert_equal "demo_reset", run.name
  end

  test "recusa fora do modo de demonstração" do
    Rails.configuration.x.demo.enabled = false
    assert_raises(Demo::Reset::Refused) { Demo::Reset.new.call }
  end

  test "a recriação diária está agendada às 4h de Brasília só com o modo ligado" do
    source = File.read(Rails.root.join("config/initializers/demo.rb"))
    assert_includes source, "America/Sao_Paulo"
    assert_includes source, "if Rails.configuration.x.demo.enabled"
    assert_equal "04:00", Demo.reset_at
  end
end
