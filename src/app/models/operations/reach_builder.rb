module Operations
  # Reconstrói o alcance das operações num credor (decisão 0024): as tabelas `operation_contracts`, `operation_customers` e `operation_bills`, que
  # as políticas do RLS consultam. É a pergunta "está pra mim?" (14, R313) calculada em conjunto, uma vez, em vez de por consulta:
  # - contrato: distribuído à operação, ou de um cliente distribuído a ela (titular ou responsável), com a exposição mais ampla;
  # - fatura retida: de promessa ou acordo em andamento feito pela operação, mesmo depois do fim da distribuição (OP-11, R317);
  # - cliente: de um contrato alcançado, ou distribuído direto.
  # Só credenciamentos ativos de operações ativas. A data de corte da exposição "vencidas" é a de hoje menos N dias úteis do credor (R319).
  # SQL de conjunto, como os recálculos do enquadramento (decisão 0021): tabela derivada, sem auditoria por linha.
  class ReachBuilder
    PROMISES_RUNNING = %w[pending open].freeze
    AGREEMENTS_RUNNING = %w[pending approved awaiting_effectuation active_on_time active_late].freeze

    def self.rebuild_all(on: Date.current) = Tenant.where(id: Accreditation.select(:tenant_id)).find_each { |tenant| new(tenant).rebuild(on: on) }

    def initialize(tenant) = @tenant = tenant

    # O corte da exposição "vencidas" em cada credor em que a operação está credenciada e ativa: { tenant_id => data }.
    def self.cutoffs(operation_id, on: Date.current)
      Tenant.where(id: Accreditation.where(operation_id: operation_id, status: "active").select(:tenant_id)).includes(:setting)
            .to_h { |tenant| [ tenant.id, new(tenant).overdue_before(on).iso8601 ] }
    end

    def rebuild(on: Date.current)
      cutoff = overdue_before(on)
      Context.system do
        ApplicationRecord.transaction do
          %w[operation_bills operation_customers operation_contracts].each { |table| sql("DELETE FROM #{table} WHERE tenant_id = $1::bigint", @tenant.id) }
          sql(<<~SQL, @tenant.id, on, cutoff)
            INSERT INTO operation_contracts (operation_id, contract_id, tenant_id, mode, overdue_before)
            SELECT x.operation_id, x.contract_id, $1::bigint, CASE WHEN bool_or(x.exposure = 'all') THEN 'all' ELSE 'overdue' END, $3::date
              FROM (SELECT d.operation_id, d.contract_id, d.exposure FROM distributions d
                     WHERE d.tenant_id = $1::bigint AND d.contract_id IS NOT NULL AND d.ended_at IS NULL AND d.starts_on <= $2::date AND (d.ends_on IS NULL OR d.ends_on >= $2::date)
                    UNION ALL
                    SELECT d.operation_id, cc.contract_id, d.exposure FROM distributions d JOIN contract_customers cc ON cc.customer_id = d.customer_id
                     WHERE d.tenant_id = $1::bigint AND d.customer_id IS NOT NULL AND d.ended_at IS NULL AND d.starts_on <= $2::date AND (d.ends_on IS NULL OR d.ends_on >= $2::date)) x
              JOIN accreditations a ON a.tenant_id = $1::bigint AND a.operation_id = x.operation_id AND a.status = 'active'
              JOIN operations o ON o.id = x.operation_id AND o.active
             GROUP BY x.operation_id, x.contract_id
          SQL
          sql(<<~SQL, @tenant.id)
            INSERT INTO operation_bills (operation_id, bill_id, tenant_id)
            SELECT DISTINCT y.operation_id, y.bill_id, $1::bigint FROM (
              SELECT p.operation_id, pb.bill_id FROM payment_promises p JOIN payment_promise_bills pb ON pb.promise_id = p.id
               WHERE p.tenant_id = $1::bigint AND p.operation_id IS NOT NULL AND p.state IN (#{quoted(PROMISES_RUNNING)})
              UNION ALL
              SELECT a.operation_id, ab.bill_id FROM agreements a JOIN agreement_bills ab ON ab.agreement_id = a.id
               WHERE a.tenant_id = $1::bigint AND a.operation_id IS NOT NULL AND a.state IN (#{quoted(AGREEMENTS_RUNNING)})
              UNION ALL
              SELECT a.operation_id, b.id FROM agreements a JOIN bills b ON b.agreement_id = a.id OR b.origin_agreement_id = a.id
               WHERE a.tenant_id = $1::bigint AND a.operation_id IS NOT NULL AND a.state IN (#{quoted(AGREEMENTS_RUNNING)})) y
              JOIN accreditations ac ON ac.tenant_id = $1::bigint AND ac.operation_id = y.operation_id AND ac.status = 'active'
              JOIN bills rb ON rb.id = y.bill_id
             -- Recolhido "também o que é dela" (R317): a retenção acaba nos contratos daquela distribuição.
             WHERE NOT EXISTS (SELECT 1 FROM distributions rd WHERE rd.tenant_id = $1::bigint AND rd.operation_id = y.operation_id AND rd.release_retention
                                 AND (rd.contract_id = rb.contract_id
                                      OR rd.customer_id IN (SELECT rc.customer_id FROM contract_customers rc WHERE rc.contract_id = rb.contract_id)))
          SQL
          sql(<<~SQL, @tenant.id)
            INSERT INTO operation_contracts (operation_id, contract_id, tenant_id, mode)
            SELECT DISTINCT r.operation_id, b.contract_id, $1::bigint, 'retained' FROM operation_bills r JOIN bills b ON b.id = r.bill_id WHERE r.tenant_id = $1::bigint
            ON CONFLICT DO NOTHING
          SQL
          sql(<<~SQL, @tenant.id, on)
            INSERT INTO operation_customers (operation_id, customer_id, tenant_id)
            SELECT r.operation_id, cc.customer_id, $1::bigint FROM operation_contracts r JOIN contract_customers cc ON cc.contract_id = r.contract_id WHERE r.tenant_id = $1::bigint
            UNION
            SELECT d.operation_id, d.customer_id, $1::bigint FROM distributions d
              JOIN accreditations a ON a.tenant_id = $1::bigint AND a.operation_id = d.operation_id AND a.status = 'active'
             WHERE d.tenant_id = $1::bigint AND d.customer_id IS NOT NULL AND d.ended_at IS NULL AND d.starts_on <= $2::date AND (d.ends_on IS NULL OR d.ends_on >= $2::date)
          SQL
        end
      end
    end

    # Hoje menos N dias úteis (padrão 3): a fatura que venceu antes disso está pra operação na exposição "vencidas" (R319).
    def overdue_before(on)
      days = @tenant.setting&.operation_exposure_business_days || 3
      date = on
      days.times { date = previous_business(date - 1) }
      date
    end

    private

      def previous_business(date)
        date -= 1 until Charges::BusinessDays.business?(date)
        date
      end

      def quoted(list) = list.map { |value| ActiveRecord::Base.connection.quote(value) }.join(", ")

      def sql(statement, *values)
        binds = values.map { |value| ActiveRecord::Relation::QueryAttribute.new("v", value, ActiveRecord::Type::Value.new) }
        ActiveRecord::Base.connection.exec_query(statement, "Operations::ReachBuilder", binds)
      end
  end
end
