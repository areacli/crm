require "test_helper"

# Restrições da demonstração pública (CRM_DEMO=1): o que fecha e o que o texto digitado vira.
class DemoRestrictionsTest < ActiveSupport::TestCase
  test "usuários, perfis, senha, dados do credor e contas de pagamento só se leem" do
    %w[memberships profiles settings/tenant_registries settings/payment_accounts settings/payment_accounts/activations settings/payment_accounts/connection_tests].each do |path|
      assert Demo::Restrictions.closed?(path, "update", "PATCH"), path
      assert Demo::Restrictions.closed?(path, "create", "POST"), path
      assert Demo::Restrictions.closed?(path, "destroy", "DELETE"), path
      assert_not Demo::Restrictions.closed?(path, "index", "GET"), path
    end
    assert Demo::Restrictions.closed?("passwords", "edit", "GET")
    assert Demo::Restrictions.closed?("settings/payment_accounts", "new", "GET")
    assert_not Demo::Restrictions.closed?("settings/channels", "create", "POST"), "canais de recebimento continuam abertos (a V5 cria e apaga um)"
    assert_not Demo::Restrictions.closed?("customers/contact_attempts", "create", "POST")
  end

  test "o texto digitado no acionamento e os motivos viram texto fictício" do
    params = ActionController::Parameters.new(customer_id: "1", contact_attempt: { channel: "phone", text: "Maria disse que o CPF dela é 123", contact_used: "(11) 91234-5678", save_contact: "1" })
    Demo::Restrictions.scrub!(params, "customers/contact_attempts", "create")
    assert_equal Demo::Restrictions::TEXT, params[:contact_attempt][:text]
    assert_equal Demo::Restrictions::CONTACT, params[:contact_attempt][:contact_used]
    assert_equal "0", params[:contact_attempt][:save_contact]
    assert_equal "phone", params[:contact_attempt][:channel]

    reason = ActionController::Parameters.new(promise: { reason: "porque sim, fulano mandou" })
    Demo::Restrictions.scrub!(reason, "promises/refusals", "create")
    assert_equal Demo::Restrictions::REASON, reason[:promise][:reason]
  end

  test "o documento digitado para anonimizar não é trocado (a conferência é do serviço), só o motivo" do
    params = ActionController::Parameters.new(anonymization: { reason: "pedido", document: "529.982.247-25" })
    Demo::Restrictions.scrub!(params, "customers/anonymizations", "create")
    assert_equal "529.982.247-25", params[:anonymization][:document]
    assert_equal Demo::Restrictions::REASON, params[:anonymization][:reason]
  end

  test "nome e contatos do cliente viram valores fictícios do mesmo formato" do
    name = ActionController::Parameters.new(customer: { name: "Fulano Real da Silva" })
    Demo::Restrictions.scrub!(name, "customers/names", "update")
    assert_match(/\ACliente fictício \d+\z/, name[:customer][:name])

    phone = ActionController::Parameters.new(contact: { kind: "phone", value: "(11) 98765-4321" })
    Demo::Restrictions.scrub!(phone, "customer_contacts", "create")
    assert_match(/\A\(11\) 9\d{4}-\d{4}\z/, phone[:contact][:value])
    assert_kind_of Registry::ParsedContact, Registry::Normalizer.phone(phone[:contact][:value])

    email = ActionController::Parameters.new(contact: { kind: "email", value: "real@gmail.com" })
    Demo::Restrictions.scrub!(email, "customer_contacts", "create")
    assert_match(/@exemplo\.com\.br\z/, email[:contact][:value])

    address = ActionController::Parameters.new(contact: { kind: "address", street: "Rua Real", number: "1", city: "Campinas", state: "SP", zip: "13010001" })
    Demo::Restrictions.scrub!(address, "customer_contacts", "create")
    assert_equal "Rua da Demonstração", address[:contact][:street]
    assert_kind_of Registry::ParsedContact, Registry::Normalizer.address(address[:contact].permit(*Tenant::ADDRESS_FIELDS).to_h.symbolize_keys)
  end

  test "campo que não veio ou veio vazio não é inventado" do
    params = ActionController::Parameters.new(contact_attempt: { channel: "phone", text: "" })
    Demo::Restrictions.scrub!(params, "customers/contact_attempts", "create")
    assert_equal "", params[:contact_attempt][:text]
    assert_not params[:contact_attempt].key?(:contact_used)
  end

  test "os índices da demonstração vêm do cliente fictício, sem Banco Central" do
    previous = Rails.configuration.x.demo.enabled
    Rails.configuration.x.demo.enabled = true
    Indexes.client = nil
    assert_kind_of Demo::IndexClient, Indexes.client
    rows = Indexes.client.series(433, from: Date.new(2020, 1, 1), to: Date.new(2020, 6, 30))
    assert_equal 6, rows.size
    assert_equal rows, Indexes.client.series(433, from: Date.new(2020, 1, 1), to: Date.new(2020, 6, 30)), "estável"
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*| raise "chamada externa" }
    begin
      Indexes::Fetch.new.call(today: Date.new(2026, 10, 25))
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
    assert_operator IndexRate.where(series: "legal").count, :>=, 80
  ensure
    Rails.configuration.x.demo.enabled = previous
  end
end
