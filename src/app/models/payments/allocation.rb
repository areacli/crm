module Payments
  # Decide o que um pagamento faz num título, dado o estado dele naquele momento (R46, R46a, R50, R51; 09, R226). Função pura: a conferência e a
  # confirmação a usam do mesmo jeito.
  module Allocation
    # applied: quanto baixa o título (todos os componentes); credit: quanto vira crédito do contrato; reason: motivo do crédito; settled: se quitou o
    # título; components: o que coube em cada componente (juros, multa, honorários, correção e principal, nessa ordem).
    #
    # `abatement`: o que o título recebeu como pago sem dinheiro, por componente, e `abatement_kind` ("creditor" ou "tolerance"): o estado final
    # "quitado" do arquivo (11, R226, N1) ou a tolerância de valor do pagamento direto (R228a). O abatimento não é dinheiro: não entra em `applied`.
    Result = Data.define(:applied, :credit, :reason, :settled, :components, :abatement, :abatement_kind) do
      def principal = components.fetch("principal", 0)

      # O que o título abate do principal: o pago mais o abatimento (o título só fica pago com o principal inteiro coberto).
      def paid_principal = principal + abatement.fetch("principal", 0)
    end

    module_function

    # `due`: quanto falta em cada componente na data do pagamento (valor atualizado, R226), com o principal no saldo atual; sem ele, o título não tem
    # encargos e o pagamento baixa só o principal (R50). O pagamento cobre os componentes na ordem de `Charges::ORDER`, e o título só fica pago quando
    # cobre o valor atualizado inteiro.
    #
    # Ordem das saídas (R226): crédito de título já pago ou retirado, valor que cobre tudo, estado final "quitado" do credor (`final_state: "settled"`),
    # tolerância de pagamento direto (`tolerance: true`; o pagamento de promessa que cai como comum não a usa) e, só então, a política de pagamento parcial (R46).
    def call(setting, bill_amount:, status:, paid:, amount:, due: nil, final_state: nil, tolerance: true)
      balance = bill_amount - paid
      due = { "principal" => [ balance, 0 ].max } if due.nil?
      total = due.values.sum

      # 11, DA8 (padrão): o pagamento a título original já renegociado vira crédito do contrato, com o motivo "título renegociado".
      return result(0, amount, "renegotiated", false, {}) if status == "renegotiated"
      # R51: título já pago (ou sem saldo) gera crédito, com o motivo "título já pago".
      return result(0, amount, "already_paid", false, {}) if status == "paid" || balance <= 0
      # R46a: título retirado, com a política "vira crédito".
      return result(0, amount, "withdrawn", false, {}) if status == "withdrawn" && setting.withdrawn_payment_policy_credit?
      # R50: valor igual ou maior que o valor atualizado quita; o que passa vira crédito do contrato (excedente).
      return result(total, amount - total, "excess", true, due) if amount >= total
      # R226, N1: o credor deu o título por quitado; a diferença é abatimento do credor. Em seguida, a tolerância de valor (R228a, N3).
      return abated(amount, due, "creditor") if final_state == "settled"
      return abated(amount, due, "tolerance") if tolerance && total - amount <= Agreements::Policies.tolerance_cents(setting, "direct", total)
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

    def result(applied, credit, reason, settled, components, abatement = {}, abatement_kind = nil)
      Result.new(applied, credit, reason, settled, components.select { |_, cents| cents.positive? }, abatement.select { |_, cents| cents.positive? }, abatement_kind)
    end

    # Título pago com abatimento: o dinheiro cobre os componentes na ordem e o que falta, "a partir do principal" (R228a), é a diferença dada por paga.
    def abated(amount, due, kind)
      parts = distribute(due, amount)
      left = due.to_h { |component, cents| [ component, cents - parts.fetch(component, 0) ] }
      result(amount, 0, "excess", true, parts, left, kind)
    end
  end
end
