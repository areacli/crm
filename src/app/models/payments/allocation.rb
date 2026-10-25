module Payments
  # Decide o que um pagamento faz num título, dado o estado dele naquele momento (R46, R46a, R50, R51; 09, R226). Função pura: a conferência e a
  # confirmação a usam do mesmo jeito.
  module Allocation
    # applied: quanto baixa o título (todos os componentes); credit: quanto vira crédito do contrato; reason: motivo do crédito; settled: se quitou o
    # título; components: o que coube em cada componente (juros, multa, honorários, correção e principal, nessa ordem).
    Result = Data.define(:applied, :credit, :reason, :settled, :components) do
      def principal = components.fetch("principal", 0)
    end

    module_function

    # `due`: quanto falta em cada componente na data do pagamento (valor atualizado, R226), com o principal no saldo atual; sem ele, o título não tem
    # encargos e o pagamento baixa só o principal (R50). O pagamento cobre os componentes na ordem de `Charges::ORDER`, e o título só fica pago quando
    # cobre o valor atualizado inteiro.
    def call(setting, bill_amount:, status:, paid:, amount:, due: nil)
      balance = bill_amount - paid
      due = { "principal" => [ balance, 0 ].max } if due.nil?
      total = due.values.sum

      # R51: título já pago (ou sem saldo) gera crédito, com o motivo "título já pago".
      return result(0, amount, "already_paid", false, {}) if status == "paid" || balance <= 0
      # R46a: título retirado, com a política "vira crédito".
      return result(0, amount, "withdrawn", false, {}) if status == "withdrawn" && setting.withdrawn_payment_policy_credit?
      # R50: valor igual ou maior que o valor atualizado quita; o que passa vira crédito do contrato (excedente).
      return result(total, amount - total, "excess", true, due) if amount >= total
      # R46: pagamento menor que o valor atualizado, com a política "crédito sem baixar".
      return result(0, amount, "without_settling", false, {}) if setting.partial_payment_policy_credit?

      result(amount, 0, "excess", false, distribute(due, amount))
    end

    # Na ordem dos componentes (juros, multa, honorários, correção, principal); só entram os que receberam algo.
    def distribute(due, amount)
      Charges::ORDER.each_with_object({}) do |component, parts|
        part = [ amount, due.fetch(component, 0) ].min
        next unless part.positive?

        parts[component] = part
        amount -= part
      end
    end

    def result(applied, credit, reason, settled, components)
      Result.new(applied, credit, reason, settled, components.select { |_, cents| cents.positive? })
    end
  end
end
