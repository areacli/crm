require "test_helper"

# A carga em massa da demonstração grava o mesmo que a confirmação normal (decisão 0021, parte 2): clientes, contatos, contratos, ligações com papéis, títulos,
# versão 1 do valor e acréscimos informados.
class DemoBulkConfirmerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def import_with(tenant, confirmer, path)
    import = Portfolio::ImportService.new.start(tenant: tenant, user: users(:joana), file: path, mode: :incremental)
    import.checker.run(import.reload)
    import.reload.then { |checked| confirmer.run(checked) }
    import.reload
  end

  def snapshot(tenant)
    {
      customers: Customer.where(tenant: tenant).order(:document).pluck(:document, :name, :name_kept),
      contacts: CustomerContact.where(tenant: tenant).joins(:customer).order("customers.document", :kind, :key).pluck("customers.document", :kind, :key, :value, :status, :reason, :origin, :city, :zip),
      contracts: Contract.where(tenant: tenant).order(:code).pluck(:code, :created_by_omission),
      links: ContractCustomer.joins(:contract, :customer).where(contracts: { tenant_id: tenant.id }).order("contracts.code", "customers.document").pluck("contracts.code", "customers.document", :roles),
      bills: Bill.where(tenant: tenant).joins(:customer, :contract).order("customers.document", :number).pluck("customers.document", :number, "contracts.code", :due_date, :amount_cents, :description, :product, :status, :paid_cents),
      versions: BillValueVersion.where(tenant: tenant).joins(:bill).order("bills.number").pluck("bills.number", :amount_cents, :user_id),
      surcharges: ReportedSurcharge.where(tenant: tenant).joins(:bill).order("bills.number").pluck("bills.number", :penalty_cents, :interest_cents)
    }
  end

  test "a confirmação em massa deixa a carteira igual à da confirmação normal" do
    path = Demo::PortfolioSheet.write(Rails.root.join("tmp", "bulk-#{SecureRandom.hex(4)}.csv").to_s, 0...120, today: Date.current)
    normal = import_with(tenants(:alfa), Portfolio::ImportConfirmer.new, path)
    bulk = import_with(tenants(:beta), Demo::BulkConfirmer.new, path)

    assert normal.confirmed? && bulk.confirmed?
    expected = snapshot(tenants(:alfa))
    assert_operator expected[:bills].size, :>, 120
    assert_operator expected[:contacts].size, :>, 100
    assert_operator expected[:surcharges].size, :>, 0
    assert expected[:links].any? { |_, _, roles| roles == [ "financial_responsible" ] }, "a planilha tem responsável financeiro"
    assert_equal expected, snapshot(tenants(:beta))
    assert_equal 0, ImportRow.where(import_id: bulk.id).count
  ensure
    FileUtils.rm_f(path) if path
  end

  test "a carga em massa recusa credor que já tem clientes" do
    path = Demo::PortfolioSheet.write(Rails.root.join("tmp", "bulk-#{SecureRandom.hex(4)}.csv").to_s, 0...5, today: Date.current)
    import = Portfolio::ImportService.new.start(tenant: tenants(:alfa), user: users(:joana), file: path, mode: :incremental)
    import.checker.run(import.reload)
    Customer.create!(tenant: tenants(:alfa), document: "52998224725", name: "Já existe")
    assert_raises(RuntimeError) { Demo::BulkConfirmer.new.run(import.reload) }
  ensure
    FileUtils.rm_f(path) if path
  end
end
