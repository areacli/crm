module Agreements
  # Crédito do contrato no acordo (11, R223, R223a, R232b): a simulação oferece o crédito disponível dos contratos dos títulos, e só desses, conforme as políticas
  # "Crédito entre contratos do acordo" (só dentro do mesmo contrato, ou soma entre eles) e "Ordem de consumo" (mais antigo primeiro, ou primeiro o do contrato do
  # título). O operador usa o crédito, no todo ou em parte, como pagamento da entrada ou como abatimento do valor do acordo (política "Como o crédito entra").
  # O crédito é consumido no aceite (lançamento negativo no contrato de origem) e volta disponível se o acordo é cancelado ou quebra antes da efetivação.
  module CreditUse
    CHANNEL_CODE = "CRM-CREDITO".freeze

    # `requested`: o que o operador pediu; `distribution`: [[id do contrato, centavos]] já na ordem de consumo; `offered`: o máximo que as políticas deixam usar;
    # `mode`: "down_payment" ou "rebate"; `error`: chave da recusa, ou nil.
    Plan = Data.define(:mode, :requested, :distribution, :offered, :error) do
      def total = distribution.sum { |_, cents| cents }
      def none? = total.zero?
      def rebate? = mode == "rebate" && !none?
      def down_payment? = mode == "down_payment" && !none?
    end

    module_function

    def none(mode = "down_payment") = Plan.new(mode, 0, [], 0, nil)

    # O que cada contrato pode dar ao acordo: o crédito disponível, limitado (só dentro do mesmo contrato) ao valor dos títulos dele no acordo. { id => centavos }.
    def usable(setting, values_by_contract)
      return {} if Policies.value(setting, "credit_use") == "record_only"

      available = Credit.available.where(contract_id: values_by_contract.keys).group(:contract_id).sum(:amount_cents)
      same = Policies.value(setting, "credit_across_contracts") == "same_contract"
      values_by_contract.to_h do |contract_id, value|
        cents = [ available.fetch(contract_id, 0), 0 ].max
        [ contract_id, same ? [ cents, value ].min : cents ]
      end.select { |_, cents| cents.positive? }
    end

    # O crédito disponível de cada contrato dos títulos, para a tela mostrar o que pode ser usado: [[contrato, centavos]]. Vazio se a política manda só registrar.
    def available_by_contract(setting, bills)
      return [] if Policies.value(setting, "credit_use") == "record_only"

      contracts = bills.map(&:contract).uniq
      sums = Credit.available.where(contract_id: contracts.map(&:id)).group(:contract_id).sum(:amount_cents)
      contracts.filter_map { |contract| [ contract, sums[contract.id] ] if sums.fetch(contract.id, 0).positive? }
    end

    # O plano de uso de `requested` centavos: a distribuição pelos contratos na ordem da política. `titles_by_contract`: o título mais antigo de cada contrato.
    def plan(setting, values_by_contract, oldest_due_by_contract, requested)
      mode = Policies.value(setting, "credit_entry")
      return none(mode) unless requested.positive?

      offers = usable(setting, values_by_contract)
      offered = offers.values.sum
      return Plan.new(mode, requested, [], offered, :above_available) if requested > offered

      order = ordered_contracts(setting, offers.keys, oldest_due_by_contract)
      left = requested
      distribution = order.filter_map do |contract_id|
        take = [ offers[contract_id], left ].min
        left -= take
        [ contract_id, take ] if take.positive?
      end
      Plan.new(mode, requested, distribution, offered, nil)
    end

    def ordered_contracts(setting, contract_ids, oldest_due_by_contract)
      if Policies.value(setting, "credit_order") == "contract_first"
        contract_ids.sort_by { |id| [ oldest_due_by_contract.fetch(id, Date.new(9999, 1, 1)), id ] }
      else
        since = Credit.available.where(contract_id: contract_ids).where("amount_cents > 0").group(:contract_id).minimum(:occurred_at)
        contract_ids.sort_by { |id| [ since.fetch(id, Time.zone.at(0)), id ] }
      end
    end

    # O abatimento do valor do acordo (R223): o crédito de cada contrato cobre o que resta dos componentes dos títulos, do mais antigo para o mais novo, na ordem
    # da 10, R195. Só dentro do mesmo contrato, o crédito de um contrato só cobre títulos dele. Devolve { índice da linha => { componente => centavos } }.
    def allocate_rebate(setting, rows, plan)
      same = Policies.value(setting, "credit_across_contracts") == "same_contract"
      credit = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      left_by_row = rows.map { |row| row.after.dup }
      groups = same ? plan.distribution.map { |contract_id, cents| [ cents, rows.each_index.select { |i| rows[i].bill.contract_id == contract_id } ] } : [ [ plan.total, rows.each_index.to_a ] ]
      groups.each do |cents, indexes|
        indexes.each do |index|
          Agreements::BASE_ORDER.each do |component|
            part = [ cents, left_by_row[index].fetch(component, 0) ].min
            next unless part.positive?

            credit[index][component] += part
            left_by_row[index][component] -= part
            cents -= part
          end
        end
      end
      credit
    end

    # --- Consumo e devolução (no aceite e no cancelamento) ---

    # Confere que o crédito de cada contrato continua disponível; devolve nil se sim, ou a chave da recusa (R220: "monte a proposta de novo").
    def unavailable(agreement)
      used(agreement).each do |contract_id, cents|
        return :credit_unavailable if Credit.available.where(contract_id: contract_id).sum(:amount_cents) < cents
      end
      nil
    end

    # O que a proposta pretende usar de cada contrato: { id do contrato => centavos }.
    def used(agreement) = agreement.terms.dig("credit", "distribution").to_a.to_h { |contract_id, cents| [ contract_id.to_i, cents.to_i ] }

    # O consumo no aceite: um lançamento negativo por contrato, com a data do aceite.
    def consume!(agreement, user, at)
      used(agreement).each do |contract_id, cents|
        Credit.create!(tenant_id: agreement.tenant_id, contract_id: contract_id, user: user, kind: :used, amount_cents: -cents, reason: :agreement, agreement_id: agreement.id,
                       occurred_at: at, note: agreement.number)
      end
    end

    # A volta do crédito não efetivado (R223, R235): um lançamento positivo por contrato, mais o estorno do pagamento feito com crédito na entrada.
    def release!(agreement, user: nil)
      used = Credit.where(agreement_id: agreement.id).group(:contract_id).sum(:amount_cents)
      used.each do |contract_id, cents|
        next unless cents.negative?

        Credit.create!(tenant_id: agreement.tenant_id, contract_id: contract_id, user: user, kind: :restored, amount_cents: -cents, reason: :agreement, agreement_id: agreement.id, note: agreement.number)
      end
    end

    # O pagamento da entrada com crédito (R223): um pagamento do canal do sistema, sem arquivo, com a data do aceite, alocado na entrada como qualquer pagamento (encargos
    # de atraso, juros e composição). Devolve o resultado da alocação, ou nil quando a proposta não usa crédito na entrada.
    def pay_down_payment!(agreement, entry, at)
      cents = agreement.credit_down_cents
      return nil unless cents.positive?

      date = at.to_date
      ledger = LedgerLoader.new(agreement.tenant, today: date).one(entry)
      result = TitlePayment.call(ledger, date: date, amount: cents, tolerance: agreement.tolerance_spec)
      payment = Payment.create!(tenant_id: agreement.tenant_id, channel: channel_for(agreement.tenant), identifier: "CRED-#{agreement.number}", document: agreement.customer.document,
                                bill_number: entry.number, bill: entry, agreement_id: agreement.id, paid_on: date, amount_cents: cents, payment_method: "other", status: "applied",
                                applied_cents: result.applied, credit_cents: result.excess)
      result.parts.each { |component, part| PaymentAllocation.create!(payment: payment, bill: entry, component: component, amount_cents: part) }
      result.abatements.each do |kind, parts|
        parts.each { |component, part| Abatement.create!(tenant_id: agreement.tenant_id, payment: payment, bill: entry, kind: kind, component: component, amount_cents: part) }
      end
      entry.update!(paid_cents: entry.paid_cents + result.face_covered, status: (result.settled ? "paid" : entry.status), paid_on: (result.settled ? date : nil))
      result
    end

    def channel_for(tenant)
      PaymentChannel.find_or_create_by!(tenant_id: tenant.id, code: CHANNEL_CODE) do |channel|
        channel.kind = :account
        channel.description = "Crédito do contrato (CRM)"
        channel.active = false
      end
    end
  end
end
