module Charges
  # Lê do banco o que o cálculo precisa dos títulos vencidos em cobrança de um credor: valor vigente, vencimento, segmento do contrato, pagamentos
  # de principal por data, encargos já alocados e histórico de segmento. Em lotes por chave (200 mil clientes não cabem de uma vez), sempre dentro
  # de um credor (V10). Consultas: `bills (tenant_id, status, due_date)` e a chave de `contracts`; `payment_allocations (bill_id)` e
  # `contract_segments (contract_id, since)`.
  class Reader
    BATCH = 20_000

    JD_2000 = Date.new(2000, 1, 1).jd
    ALLOCATIONS_SQL = <<~SQL.freeze
      select a.bill_id, p.paid_on, a.component, sum(a.amount_cents)::bigint as cents
      from payment_allocations a join payments p on p.id = a.payment_id
      where a.bill_id between ? and ? group by 1, 2, 3 having sum(a.amount_cents) <> 0
    SQL
    NONE = [].freeze
    NO_PAID = {}.freeze
    NO_DATES = Set.new.freeze

    Input = Struct.new(:bill_id, :customer_id, :contract_id, :amount, :due, :segment_id, :payments, :periods, :paid, :dates)

    # `bill_ids` limita a esses títulos (ficha, pagamento); `segment_ids`, aos contratos que passaram por esses segmentos (conferência do impacto).
    # `unsegmented`: com `segment_ids`, inclui também os contratos ainda sem segmento (valem como "Demais" até o primeiro recálculo dos segmentos).
    def initialize(tenant, today:, bill_ids: nil, segment_ids: nil, unsegmented: false)
      @unsegmented = unsegmented
      @tenant = tenant
      @today = today
      @bill_ids = bill_ids
      @segment_ids = segment_ids
    end

    def each_batch
      last = 0
      loop do
        rows = bills(last)
        break if rows.empty?

        last = rows.last[0]
        yield inputs(rows)
        break if rows.size < BATCH
      end
    end

    private
      def bills(after)
        where = [ "b.tenant_id = :t", "b.status = 'active'", "b.kind = 'common'", "b.due_date < :today", "b.id > :after" ]
        where << "b.id in (:ids)" if @bill_ids
        where << "(#{'c.segment_id is null or ' if @unsegmented}c.segment_id in (:segments) or exists (select 1 from contract_segments cs where cs.contract_id = b.contract_id and cs.segment_id in (:segments)))" if @segment_ids
        sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { t: @tenant.id, today: @today, after: after, ids: @bill_ids || [ 0 ], segments: @segment_ids || [ 0 ] } ])
          select b.id, b.customer_id, b.contract_id, b.amount_cents, (b.due_date - date '2000-01-01') as due_days, c.segment_id
          from bills b join contracts c on c.id = b.contract_id
          where #{where.join(' and ')} order by b.id limit #{BATCH}
        SQL
        ActiveRecord::Base.connection.select_rows(sql)
      end

      def contracts_with_history(contracts)
        Portfolio::Sql.rows("select contract_id from contract_segments where contract_id in (?) group by contract_id having count(*) > 1", contracts).map { |row| row["contract_id"].to_i }
      end

      # Os contratos do credor com mais de uma linha de histórico, lidos uma vez por leitura (uma agregação).
      def multi_history_contracts
        @multi_history_contracts ||= Portfolio::Sql.rows(<<~SQL, @tenant.id).map { |row| row["contract_id"].to_i }
          select cs.contract_id from contract_segments cs join contracts c on c.id = cs.contract_id
          where c.tenant_id = ? group by cs.contract_id having count(*) > 1
        SQL
      end

      def inputs(rows)
        low = rows.first[0]
        high = rows.last[0]
        payments = Hash.new { |hash, key| hash[key] = [] }
        paid = Hash.new { |hash, key| hash[key] = {} }
        dates = Hash.new { |hash, key| hash[key] = Set.new }
        # Leitura inteira: os títulos do lote são um intervalo de chaves (lidos em ordem), e o intervalo vale mais que uma lista de 20 mil números na
        # consulta. Leitura de poucos títulos (a baixa dos pagamentos de uma carga, a ficha): a lista, que não varre o intervalo todo.
        allocations = if @bill_ids
          Portfolio::Sql.rows(ALLOCATIONS_SQL.sub("a.bill_id between ? and ?", "a.bill_id in (?)"), rows.map(&:first))
        else
          Portfolio::Sql.rows(ALLOCATIONS_SQL, low, high)
        end
        allocations.each do |row|
          bill_id = row["bill_id"].to_i
          cents = row["cents"].to_i
          date = row["paid_on"].is_a?(Date) ? row["paid_on"] : Date.parse(row["paid_on"].to_s)
          dates[bill_id] << date if cents.positive?
          if row["component"] == "principal"
            payments[bill_id] << [ date, cents ]
          else
            paid[bill_id][row["component"]] = paid[bill_id].fetch(row["component"], 0) + cents
          end
        end
        history = Hash.new { |hash, key| hash[key] = [] }
        # Contrato com uma só linha de histórico calcula como sem histórico (o primeiro segmento vale antes dele, DE4): só os de mais de uma linha vêm.
        contracts = rows.map { |row| row[2] }.uniq
        moved = @bill_ids ? contracts_with_history(contracts) : contracts & multi_history_contracts
        if moved.any?
          Portfolio::Sql.rows("select cs.contract_id, cs.since, cs.segment_id from contract_segments cs where cs.contract_id in (?) order by cs.contract_id, cs.since", moved).each do |row|
            history[row["contract_id"].to_i] << [ Date.parse(row["since"].to_s), row["segment_id"]&.to_i ]
          end
        end
        rows.map do |id, customer_id, contract_id, amount, due, segment_id|
          Input.new(id.to_i, customer_id.to_i, contract_id.to_i, amount.to_i, Date.jd(JD_2000 + due.to_i), segment_id&.to_i,
                    payments.fetch(id.to_i, NONE), history.fetch(contract_id.to_i, NONE), paid.fetch(id.to_i, NO_PAID), dates.fetch(id.to_i, NO_DATES))
        end
      end
  end
end
