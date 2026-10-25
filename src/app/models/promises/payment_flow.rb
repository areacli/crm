module Promises
  # O pagamento de promessa dentro da confirmação (e da conferência) de pagamentos (10, R194 a R196, R198): a linha traz o número da promessa no lugar do
  # número do título (DP8). Pelo meio combinado e com data entre o contato e a data prometida, o pagamento é alocado nos títulos dela, do mais antigo para
  # o mais novo, encargos antes do principal, até o valor de cada título na promessa; fora disso é pagamento comum dos mesmos títulos. Título que deixou de
  # estar apto (pago por fora, retirado) fica fora e a diferença vira crédito do contrato (R195b, R195c). Os dados da promessa são lidos em lote e o que o
  # arquivo aloca fica na memória até o fim de cada lote, como no `Payments::Processor`.
  class PaymentFlow
    Sql = Portfolio::Sql

    Handle = Struct.new(:id, :contract_id, :state, :payment_method, :contacted_on, :promised_on, :policies, :paid_cents, :lines, :dirty, keyword_init: true)
    Line = Struct.new(:row_id, :bill_id, :due_date, :amount_cents, :frozen, :paid, :dirty, keyword_init: true)
    Outcome = Struct.new(:applied, :credit, :reason, :allocations, :counted, :settled, :partial, :contract_id, keyword_init: true)

    attr_reader :touched

    # Títulos que pertencem a alguma promessa do credor: o estado deles atravessa os lotes pela memória (ver Payments::BillStates).
    def self.shared_bill_ids(tenant_id)
      Sql.rows("select distinct pb.bill_id from payment_promise_bills pb join payment_promises p on p.id = pb.promise_id where p.tenant_id = ? and pb.removed_at is null",
               tenant_id).to_set { |row| row["bill_id"].to_i }
    end

    def initialize(tenant, setting, states, charges)
      @tenant_id = tenant.id
      @setting = setting
      @states = states
      @charges = charges
      @handles = {}
      @snapshot = {}
      @touched = Set.new
      # Política "também os pagamentos diretos aos títulos" (DP1): título => promessa aberta que os conta.
      @direct = Sql.rows(<<~SQL, @tenant_id).to_h { |row| [ row["bill_id"].to_i, row["promise_id"].to_i ] }
        select pb.bill_id, pb.promise_id from payment_promise_bills pb join payment_promises p on p.id = pb.promise_id
        where p.tenant_id = ? and p.state = 'open' and pb.held and pb.removed_at is null and p.policies->>'counting' = 'also_direct'
      SQL
    end

    def direct_promise_for(bill_id) = @direct[bill_id]

    # Carrega o que o lote vai usar: as promessas das linhas, as que contam os pagamentos diretos dos títulos do lote e o estado atual dos títulos delas.
    def begin_lot(rows)
      ids = rows.filter_map { |row| row["promise_id"]&.to_i }
      ids |= rows.filter_map { |row| @direct[row["bill_id"].to_i] if row["bill_id"] }
      load(ids)
      bill_ids = ids.flat_map { |id| @handles.fetch(id).lines.map(&:bill_id) }
      @charges&.preload(bill_ids)
      @snapshot = {}
      bill_ids.each_slice(2000) do |slice|
        Sql.rows("select id, paid_cents, status, paid_on from bills where id in (?)", slice).each do |row|
          @snapshot[row["id"].to_i] = [ row["paid_cents"].to_i, row["status"], to_date(row["paid_on"]) ]
        end
      end
    end

    # Paga a promessa `promise_id` com `amount` (R194 a R196). Devolve o que foi alocado em cada título, o crédito e se contou para a promessa.
    def settle(promise_id, amount:, pay_date:, method:)
      handle = @handles.fetch(promise_id)
      @touched << promise_id
      counts = counts?(handle, method, pay_date)
      outcome = Outcome.new(applied: 0, credit: 0, reason: "excess", allocations: [], counted: counts, settled: 0, partial: 0, contract_id: handle.contract_id)
      # DP11: com a política "a R46 vale também na promessa", o pagamento menor que o valor vira crédito sem baixar, se o credor assim o quer.
      if counts && handle.policies["partial"] == "r46" && @setting.partial_payment_policy_credit? && amount < wanted_total(handle)
        outcome.credit = amount
        outcome.reason = "without_settling"
        return outcome
      end

      remaining = amount
      stop = false
      handle.lines.each do |line|
        break if remaining <= 0 || stop

        paid, status, = state_of(line.bill_id)
        next unless status == "active" # R195b: título que não está mais apto fica fora

        if counts
          remaining = counted_part(handle, line, outcome, remaining, pay_date)
        else
          remaining, stop = common_part(line, outcome, remaining, pay_date, paid)
        end
      end
      outcome.credit = remaining
      outcome.reason = "already_paid" if outcome.applied.zero? && outcome.reason == "excess"
      handle.dirty = true if outcome.counted
      outcome
    end

    # DP1: o pagamento direto a um título de promessa aberta conta para ela quando o meio e a data são os combinados (R194).
    def count_direct(promise_id, bill_id, method, pay_date, components)
      handle = @handles[promise_id] or return false
      return false unless counts?(handle, method, pay_date) && handle.state == "open"

      line = handle.lines.find { |item| item.bill_id == bill_id } or return false
      components.each { |component, cents| line.paid[component] = line.paid.fetch(component, 0) + cents }
      line.dirty = true
      handle.paid_cents += components.values.sum
      handle.dirty = true
      @touched << promise_id
      true
    end

    # Grava o que os pagamentos que contam alocaram (só na confirmação).
    def flush
      lines = []
      promises = []
      @handles.each_value do |handle|
        next unless handle.dirty

        promises << [ handle.id, handle.paid_cents ]
        handle.lines.each { |line| lines << [ line.row_id, line.paid ] if line.dirty }
        handle.dirty = false
        handle.lines.each { |line| line.dirty = false }
      end
      connection = Sql.connection
      lines.each_slice(2000) do |slice|
        values = slice.map { |id, paid| "(#{id.to_i}::bigint, #{connection.quote(paid.to_json)}::jsonb)" }.join(",")
        Sql.run("update payment_promise_bills set paid = v.paid from (values #{values}) as v(id, paid) where payment_promise_bills.id = v.id")
      end
      promises.each_slice(2000) do |slice|
        values = slice.map { |id, paid| "(#{id.to_i}::bigint, #{paid.to_i}::bigint)" }.join(",")
        Sql.run("update payment_promises set paid_cents = v.paid, updated_at = now() from (values #{values}) as v(id, paid) where payment_promises.id = v.id")
      end
    end

    private
      # R194, R198: conta quando o meio é o combinado e a data está entre o contato e a data prometida; a quebrada conta se a política manda (DP2).
      def counts?(handle, method, pay_date)
        return false unless handle.state == "open" || (handle.state == "broken" && handle.policies["after_break"] == "fulfilled")

        method == handle.payment_method && pay_date >= handle.contacted_on && pay_date <= handle.promised_on
      end

      def wanted_total(handle)
        handle.lines.sum do |line|
          paid, status, = state_of(line.bill_id)
          status == "active" ? wanted(line, paid).values.sum : 0
        end
      end

      # O que falta cobrir no título: o valor congelado menos o já alocado, com o principal limitado ao saldo atual.
      def wanted(line, paid)
        want = line.frozen.to_h { |component, cents| [ component, cents - line.paid.fetch(component, 0) ] }
        want["principal"] = [ want.fetch("principal", 0), [ line.amount_cents - paid, 0 ].max ].min
        want.select { |_, cents| cents.positive? }
      end

      def state_of(bill_id) = @states.get(bill_id) || @snapshot.fetch(bill_id)

      # Pagamento que conta: encargos antes do principal, até o valor do título na promessa (R195). Devolve o que sobrou.
      def counted_part(handle, line, outcome, remaining, pay_date)
        paid, = state_of(line.bill_id)
        parts = Payments::Allocation.distribute(wanted(line, paid), remaining)
        return remaining if parts.empty?

        cents = parts.values.sum
        parts.each { |component, part| line.paid[component] = line.paid.fetch(component, 0) + part }
        line.dirty = true
        handle.paid_cents += cents
        new_paid = paid + parts.fetch("principal", 0)
        settled = new_paid >= line.amount_cents
        @states.put(line.bill_id, paid: new_paid, status: settled ? "paid" : "active", paid_on: settled ? pay_date : nil, keep: true)
        outcome.allocations << [ line.bill_id, parts ]
        outcome.applied += cents
        if settled then outcome.settled += 1 else outcome.partial += 1 end
        remaining - cents
      end

      # Pagamento que não conta (outro meio, fora da janela ou promessa encerrada): vai aos títulos como pagamento comum, do mais antigo para o mais novo
      # (R194), pela mesma alocação da baixa (R226). Devolve o que sobrou e se o pagamento parou neste título (pagamento parcial).
      def common_part(line, outcome, remaining, pay_date, paid)
        due = @charges&.due(line.bill_id, pay_date, [ line.amount_cents - paid, 0 ].max)
        result = Payments::Allocation.call(@setting, bill_amount: line.amount_cents, status: "active", paid: paid, amount: remaining, due: due)
        @charges&.record(line.bill_id, pay_date, result.components)
        new_paid = paid + result.principal
        @states.put(line.bill_id, paid: new_paid, status: result.settled ? "paid" : "active", paid_on: result.settled ? pay_date : nil, keep: true)
        outcome.allocations << [ line.bill_id, result.components ] if result.components.any?
        outcome.applied += result.applied
        if result.settled
          outcome.settled += 1
          [ result.credit, false ]
        else
          outcome.partial += 1 if result.applied.positive?
          outcome.reason = result.reason if result.credit.positive?
          [ result.credit, true ]
        end
      end

      def load(ids)
        missing = ids - @handles.keys
        return if missing.empty?

        Sql.rows("select id, contract_id, state, payment_method, contacted_on, promised_on, policies, paid_cents from payment_promises where tenant_id = ? and id in (?)",
                 @tenant_id, missing).each do |row|
          @handles[row["id"].to_i] = Handle.new(id: row["id"].to_i, contract_id: row["contract_id"].to_i, state: row["state"], payment_method: row["payment_method"],
                                                contacted_on: to_date(row["contacted_on"]), promised_on: to_date(row["promised_on"]), policies: json(row["policies"]),
                                                paid_cents: row["paid_cents"].to_i, lines: [], dirty: false)
        end
        Sql.rows(<<~SQL, @handles.keys & missing).each do |row|
          select pb.id, pb.promise_id, pb.bill_id, pb.principal_cents, pb.correction_cents, pb.fine_cents, pb.interest_cents, pb.fees_cents, pb.paid, b.due_date, b.amount_cents
          from payment_promise_bills pb join bills b on b.id = pb.bill_id
          where pb.promise_id in (?) and pb.removed_at is null order by b.due_date, b.id
        SQL
          frozen = PaymentPromiseBill::COLUMNS.to_h { |component, column| [ component, row[column.to_s].to_i ] }.select { |_, cents| cents.positive? }
          @handles.fetch(row["promise_id"].to_i).lines << Line.new(row_id: row["id"].to_i, bill_id: row["bill_id"].to_i, due_date: to_date(row["due_date"]),
                                                                    amount_cents: row["amount_cents"].to_i, frozen: frozen, paid: json(row["paid"]), dirty: false)
        end
      end

      def to_date(value) = value.nil? ? nil : (value.is_a?(Date) ? value : Date.parse(value.to_s))

      def json(value) = value.is_a?(String) ? JSON.parse(value) : (value || {})
  end
end
