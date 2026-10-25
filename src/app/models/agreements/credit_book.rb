module Agreements
  # O livro do crédito do contrato por estado (11, R232b, R233, R239; dominio.md): só inserção, o saldo de cada estado é a soma dos lançamentos do balde. Passar de um estado a outro
  # (disponível, aguardando alocação, bloqueado) é um par de lançamentos de soma zero; usar, transferir e estornar são lançamentos negativos num balde.
  module CreditBook
    module_function

    # O saldo do contrato num balde.
    def balance(contract_id, bucket = "available") = Credit.where(contract_id: contract_id, bucket: bucket).sum(:amount_cents)

    # Passa `cents` de um balde a outro no mesmo contrato (a soma do contrato não muda). Devolve os centavos efetivamente passados (nunca mais do que o balde tem).
    def move!(contract_id, from:, to:, cents:, reason:, user: nil, payment_id: nil, agreement_id: nil, note: nil, at: Time.current)
      cents = [ cents, balance(contract_id, from) ].min
      return 0 unless cents.positive?

      tenant_id = Contract.where(id: contract_id).pick(:tenant_id)
      common = { tenant_id: tenant_id, contract_id: contract_id, user_id: user&.id, kind: "moved", reason: reason, payment_id: payment_id, agreement_id: agreement_id, note: note, occurred_at: at }
      Credit.create!(common.merge(bucket: from, amount_cents: -cents))
      Credit.create!(common.merge(bucket: to, amount_cents: cents))
      cents
    end

    # O dia em que o crédito que vai ser consumido ficou disponível para o contrato (W4, Z9): o uso consome primeiro o disponível há mais tempo, e, com vários lançamentos, vale o mais
    # recente entre os consumidos.
    def availability_date(contract_id, cents)
      entries = Credit.available.where(contract_id: contract_id).order(:occurred_at, :id).to_a
      spent = -entries.select { |entry| entry.amount_cents.negative? }.sum(&:amount_cents)
      date = nil
      entries.select { |entry| entry.amount_cents.positive? }.each do |entry|
        skip = [ spent, entry.amount_cents ].min
        spent -= skip
        left = entry.amount_cents - skip
        next unless left.positive? && cents.positive?

        cents -= left
        date = entry.occurred_at.to_date
      end
      date || Date.current
    end

    # Lança crédito novo (positivo) no contrato, no balde dado.
    def add!(contract_id, cents, reason:, bucket: "available", kind: "entry", user: nil, payment_id: nil, agreement_id: nil, bill_id: nil, note: nil, at: Time.current, tenant_id: nil)
      tenant_id ||= Contract.where(id: contract_id).pick(:tenant_id)
      Credit.create!(tenant_id: tenant_id, contract_id: contract_id, user_id: user&.id, kind: kind, amount_cents: cents, bucket: bucket, reason: reason, payment_id: payment_id,
                     agreement_id: agreement_id, bill_id: bill_id, note: note, occurred_at: at)
    end

    # Tira `cents` do balde (lançamento negativo). `kind`: o tipo do lançamento (used, reversal, manager).
    def take!(contract_id, cents, kind:, reason:, bucket: "available", user: nil, payment_id: nil, agreement_id: nil, bill_id: nil, note: nil, at: Time.current, tenant_id: nil)
      add!(contract_id, -cents, reason: reason, bucket: bucket, kind: kind, user: user, payment_id: payment_id, agreement_id: agreement_id, bill_id: bill_id, note: note, at: at, tenant_id: tenant_id)
    end
  end
end
