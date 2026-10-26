module Promises
  # Avaliação das promessas depois de pagamentos, estornos e cargas (10, R193, R196, R198, R199): decide em lote quais ficam cumpridas, cumpridas com atraso
  # ou canceladas, e reabre ou quebra a cumprida cujo pagamento foi estornado. A tarefa diária (`Daily`) quebra as vencidas. As consultas são SQL de conjunto
  # (só leem); a gravação é Active Record (decisão 0021), com a auditoria única (`Change.record_many!`) e um aviso só ao fim do lote.
  class Evaluator
    Sql = Portfolio::Sql
    SLICE = 2000

    # Promessas pendentes, abertas ou quebradas dos títulos dados: as que um pagamento comum a um título pode ter completado (R193, R196).
    def self.promises_of_bills(bill_ids, states: %w[pending open broken])
      return [] if bill_ids.empty?

      bill_ids.each_slice(SLICE).flat_map do |slice|
        Sql.rows(<<~SQL, slice, states).map { |row| row["promise_id"].to_i }
          select distinct pb.promise_id from payment_promise_bills pb join payment_promises p on p.id = pb.promise_id
          where pb.bill_id in (?) and pb.removed_at is null and p.state in (?)
        SQL
      end.uniq
    end

    def initialize(tenant_id, actor: nil)
      @tenant_id = tenant_id
      @actor = actor
    end

    # Cumprimento (R196): pagamentos que contam somam o valor da promessa (ou a tolerância de valor, DP-T), ou todos os títulos liquidados com algum
    # pagamento dela; todos liquidados só por pagamentos depois da data prometida, cumprida com atraso (revisão 2); liquidados por fora até a data, cancelada.
    def evaluate(promise_ids)
      changed = Hash.new { |hash, key| hash[key] = [] }
      promise_ids.each_slice(SLICE) do |slice|
        facts(slice).each do |fact|
          verdict = verdict_of(fact)
          changed[verdict] << fact[:id] if verdict
        end
      end
      apply(changed)
    end

    # R199: o estorno reabre a cumprida que ainda está no prazo, ou a quebra se o prazo passou; só muda quem deixou de cumprir.
    def reassess(promise_ids)
      reopened = []
      broken = []
      promise_ids.each_slice(SLICE) do |slice|
        facts(slice, states: %w[fulfilled fulfilled_late]).each do |fact|
          next if %w[fulfilled fulfilled_late].include?(verdict_of(fact.merge(state: "open"))&.first)

          (Date.current <= fact[:deadline] ? reopened : broken) << fact[:id]
        end
      end
      broken |= reopen(reopened)
      broken.each_slice(SLICE) { |slice| back_to(slice, "broken") }
      Broadcast.changed(Tenant.find(@tenant_id)) if (reopened + broken).any?
    end

    private
      # Uma linha por promessa: o que o veredito precisa saber dos títulos dela, em uma consulta (índice `payment_promise_bills (promise_id, bill_id)`).
      def facts(ids, states: %w[pending open broken])
        Sql.rows(<<~SQL, @tenant_id, ids, states).map do |row|
          select p.id, p.state, p.promised_on, p.paid_cents, p.policies,
                 coalesce(sum(pb.total_cents), 0) as total, count(*) as n, count(*) filter (where b.status = 'paid') as n_paid, max(b.paid_on) as last_paid_on
          from payment_promises p join payment_promise_bills pb on pb.promise_id = p.id and pb.removed_at is null join bills b on b.id = pb.bill_id
          where p.tenant_id = ? and p.id in (?) and p.state in (?) group by p.id
        SQL
          policies = row["policies"].is_a?(String) ? JSON.parse(row["policies"]) : row["policies"]
          promised_on = row["promised_on"].is_a?(Date) ? row["promised_on"] : Date.parse(row["promised_on"].to_s)
          last_paid_on = row["last_paid_on"] && (row["last_paid_on"].is_a?(Date) ? row["last_paid_on"] : Date.parse(row["last_paid_on"].to_s))
          { id: row["id"].to_i, state: row["state"], promised_on: promised_on, paid: row["paid_cents"].to_i, total: row["total"].to_i, all_paid: row["n"] == row["n_paid"],
            last_paid_on: last_paid_on, min_pct: policies["min_paid_pct"], deadline: promised_on + policies.fetch("tolerance_days", 3).to_i.days }
        end
      end

      # O estado novo e o motivo, ou nil quando nada muda.
      def verdict_of(fact)
        reached = fact[:paid].positive? && (fact[:paid] >= fact[:total] || (fact[:min_pct] && fact[:paid] * 100 >= fact[:min_pct] * fact[:total]))
        if fact[:state] == "pending"
          return [ "canceled", "títulos pagos fora da promessa" ] if fact[:all_paid]
        elsif reached || (fact[:all_paid] && fact[:paid].positive?)
          return [ "fulfilled", nil ]
        elsif fact[:all_paid] && fact[:last_paid_on] && fact[:last_paid_on] > fact[:promised_on]
          return [ "fulfilled_late", nil ]
        elsif fact[:all_paid] && fact[:state] == "open"
          return [ "canceled", "títulos pagos fora da promessa" ]
        end
        nil
      end

      def apply(changed)
        changed.each do |(state, reason), ids|
          ids.each_slice(SLICE) { |slice| close(slice, state, reason) }
        end
        return if changed.empty?

        Broadcast.changed(Tenant.find(@tenant_id), customers_of(changed.values.flatten.first(200)))
      end

      def close(ids, state, reason)
        move_to(ids, state, reason: reason)
        PaymentPromiseBill.where(promise_id: ids, held: true).update_all(held: false)
      end

      # Quebrada ou aberta de novo por estorno: o estado volta sem data de encerramento quando reabre.
      def back_to(ids, state)
        move_to(ids, state)
      end

      # Muda o estado das promessas (com a regra do percentual pago) e registra cada mudança no histórico. Uma transação por fatia.
      def move_to(ids, state, **extra)
        promises = PaymentPromise.where(id: ids).preload(:customer, :contract, :contact_attempt).to_a
        entries = []
        Broadcast.quiet do
          ApplicationRecord.transaction do
            promises.each do |promise|
              before = promise.state
              promise.update!(state: state, closed_at: Time.current, paid_percent: promise.paid_percent_value, **extra)
              entries << [ promise, "state_changed", { field: "state", before: before, after: state, note: extra[:reason] } ]
            end
            Change.record_many!(entries, tenant_id: @tenant_id, actor: @actor)
          end
        end
      end

      # R199 e PR-7: reabre prendendo os títulos de novo; se algum já está numa promessa pendente ou aberta, a anterior fica quebrada (nunca duas).
      # Devolve as que não puderam reabrir (algum título já está em outra promessa).
      def reopen(ids)
        refused = []
        ids.each_slice(SLICE) do |slice|
          conflicted = Sql.rows(<<~SQL, slice, slice).map { |row| row["promise_id"].to_i }
            select distinct pb.promise_id from payment_promise_bills pb
            where pb.promise_id in (?) and pb.removed_at is null and exists (select 1 from payment_promise_bills o where o.bill_id = pb.bill_id and o.held and o.promise_id not in (?))
          SQL
          refused.concat(conflicted)
          free = slice - conflicted
          next if free.empty?

          promises = PaymentPromise.where(id: free).preload(:customer, :contract, :contact_attempt).to_a
          entries = []
          Broadcast.quiet do
            ApplicationRecord.transaction do
              promises.each do |promise|
                before = promise.state
                promise.update!(state: "open", closed_at: nil, paid_percent: nil, reason: nil)
                entries << [ promise, "state_changed", { field: "state", before: before, after: "open" } ]
              end
              PaymentPromiseBill.where(promise_id: free, removed_at: nil).update_all(held: true)
              Change.record_many!(entries, tenant_id: @tenant_id, actor: @actor)
            end
          end
        end
        refused
      end

      def customers_of(ids)
        Sql.rows("select distinct cc.customer_id from payment_promises p join contract_customers cc on cc.contract_id = p.contract_id where p.id in (?)", ids).map { |row| row["customer_id"].to_i }
      end
  end
end
