module Payments
  # Decide o que um pagamento faz num título, dado o estado dele naquele momento (R46, R46a, R50, R51). Função pura: a conferência e a
  # confirmação a usam do mesmo jeito.
  module Allocation
    # applied: quanto baixa o título; credit: quanto vira crédito do contrato; reason: motivo do crédito; settled: se quitou o título.
    Result = Data.define(:applied, :credit, :reason, :settled)

    module_function

    def call(setting, bill_amount:, status:, paid:, amount:)
      balance = bill_amount - paid

      # R51: título já pago (ou sem saldo) gera crédito, com o motivo "título já pago".
      return Result.new(0, amount, "already_paid", false) if status == "paid" || balance <= 0
      # R46a: título retirado, com a política "vira crédito".
      return Result.new(0, amount, "withdrawn", false) if status == "withdrawn" && setting.withdrawn_payment_policy_credit?
      # R50: valor igual ou maior que o saldo quita; o que passa vira crédito do contrato (excedente).
      return Result.new(balance, amount - balance, "excess", true) if amount >= balance
      # R46: pagamento menor que o saldo, com a política "crédito sem baixar".
      return Result.new(0, amount, "without_settling", false) if setting.partial_payment_policy_credit?

      Result.new(amount, 0, "excess", false)
    end
  end
end
