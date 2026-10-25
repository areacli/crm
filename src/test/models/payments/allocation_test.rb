require "test_helper"

# R46, R46a, R50 e R51: o que um pagamento faz num título, com cada opção das políticas do credor e o padrão.
class Payments::AllocationTest < ActiveSupport::TestCase
  setup { @setting = tenants(:alfa).setting }

  def allocate(amount, status: "active", paid: 0, bill_amount: 100_000)
    Payments::Allocation.call(@setting, bill_amount: bill_amount, status: status, paid: paid, amount: amount)
  end

  test "valor igual ao saldo quita o título (R50)" do
    result = allocate(100_000)
    assert_equal [ 100_000, 0, true ], [ result.applied, result.credit, result.settled ]
  end

  test "o que passa do saldo vira crédito do contrato, com o motivo excedente (R50)" do
    result = allocate(65_000, paid: 40_000, bill_amount: 100_000)
    assert_equal [ 60_000, 5_000, "excess", true ], [ result.applied, result.credit, result.reason, result.settled ]
  end

  test "pagamento menor que o saldo, política padrão: baixa parcial (R46)" do
    assert_predicate @setting, :partial_payment_policy_partial?
    result = allocate(40_000)
    assert_equal [ 40_000, 0, false ], [ result.applied, result.credit, result.settled ]
  end

  test "pagamento menor que o saldo, política crédito sem baixar (R46)" do
    @setting.partial_payment_policy = :credit
    result = allocate(40_000)
    assert_equal [ 0, 40_000, "without_settling", false ], [ result.applied, result.credit, result.reason, result.settled ]
  end

  test "pagamento que quita não é afetado pela política de crédito sem baixar" do
    @setting.partial_payment_policy = :credit
    assert_predicate allocate(100_000), :settled
  end

  test "título já pago: o valor inteiro vira crédito com o motivo título já pago (R51)" do
    result = allocate(20_000, status: "paid", paid: 100_000)
    assert_equal [ 0, 20_000, "already_paid" ], [ result.applied, result.credit, result.reason ]
  end

  test "título retirado, política padrão: o pagamento prevalece (R46a)" do
    assert_predicate @setting, :withdrawn_payment_policy_prevails?
    result = allocate(100_000, status: "withdrawn")
    assert_equal [ 100_000, 0, true ], [ result.applied, result.credit, result.settled ]
  end

  test "título retirado, parcial: segue a política da R46 e o título continua retirado" do
    result = allocate(30_000, status: "withdrawn")
    assert_equal [ 30_000, 0, false ], [ result.applied, result.credit, result.settled ]
  end

  test "título retirado, política vira crédito: o título não muda e o valor vira crédito (R46a)" do
    @setting.withdrawn_payment_policy = :credit
    result = allocate(50_000, status: "withdrawn")
    assert_equal [ 0, 50_000, "withdrawn", false ], [ result.applied, result.credit, result.reason, result.settled ]
  end
end
