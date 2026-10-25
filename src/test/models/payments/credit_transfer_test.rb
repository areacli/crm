require "test_helper"

# Transferência de crédito entre contratos do mesmo credor (R55a, R55b).
class Payments::CreditTransferTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @from = make_bill(@alfa, number: "NF-1", contract_code: "C-1").contract
    @to = make_bill(@alfa, number: "NF-2", contract_code: "C-2", document: JOAO, name: "Carlos").contract
    Credit.create!(tenant: @alfa, contract: @from, kind: :entry, amount_cents: 20_000, reason: :excess)
    @service = Payments::CreditTransfer.new(users(:joana))
  end

  def transfer(cents = 15_000, reason: "título migrado de contrato", from: @from, to: @to) = @service.transfer(from: from, to: to, cents: cents, reason: reason)

  test "transfere parte do crédito entre contratos de clientes diferentes, com dois lançamentos que somam zero e o registro" do
    transfer
    assert_equal [ 5_000, 15_000 ], [ @from.credit_cents, @to.credit_cents ]
    out, incoming = Credit.where(reason: :transfer).order(:id).to_a
    assert_equal [ "transfer_out", -15_000, @to.id, users(:joana).id ], [ out.kind, out.amount_cents, out.related_contract_id, out.user_id ]
    assert_equal [ "transfer_in", 15_000, @from.id, "título migrado de contrato" ], [ incoming.kind, incoming.amount_cents, incoming.related_contract_id, incoming.note ]
    assert_equal 20_000, Credit.where(tenant: @alfa).sum(:amount_cents), "o total do credor não muda"
    assert_equal 2, Change.where(event: "credit_transferred").count
  end

  test "recusa sem motivo, valor zero, destino igual, destino de outro credor e valor acima do disponível" do
    beta_contract = make_bill(tenants(:beta), number: "NF-B", contract_code: "C-B").contract
    [ [ { reason: " " }, "Informe o motivo" ], [ { cents: 0 }, "maior que zero" ], [ { to: @from }, "diferente" ], [ { to: beta_contract }, "mesmo credor" ],
      [ { cents: 20_001 }, "maior que o crédito disponível" ] ].each do |options, message|
      error = assert_raises(Access::Refused) { transfer(options.fetch(:cents, 1_000), **options.except(:cents)) }
      assert_includes error.message, message
    end
    assert_equal 1, Credit.count
  end

  test "o crédito não muda de contrato quando uma carga troca o contrato do título (MT-24)" do
    bill = @from.bills.first
    bill.update!(contract: @to)
    assert_equal [ 20_000, 0 ], [ @from.credit_cents, @to.credit_cents ]
  end

  test "o livro de crédito é só inserção" do
    credit = Credit.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { credit.update!(note: "x") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { credit.destroy }
  end
end
