module Segments
  # Calcula o segmento de cada contrato do credor com título em cobrança (R150, R152), numa consulta só por credor (decisão 0004). Os segmentos
  # entram como lista de entradas (hashes) em ordem, para servir tanto ao vigente quanto a uma proposta em conferência. A primeira entrada ativa
  # que casar vale (R149); o "Demais" fecha a lista. Título em cobrança é o título ativo; com "só na ficha" (R19a), só o vencido conta.
  # Consultas e índices: `bills (tenant_id, status, due_date)` lê os títulos do credor; `contract_customers` e `contracts` por chave primária.
  class Calculator
    ACCENTED = Portfolio::Query::ACCENTED
    PLAIN = Portfolio::Query::PLAIN

    def initialize(tenant, entries:, policy:, today: Date.current)
      @tenant = tenant
      @entries = entries
      @policy = policy
      @today = today
    end

    # Linhas: contract_id, old_segment_id, new_segment_id, balance_cents, person_type.
    def sql
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { today: @today } ])
        select x.contract_id, x.old_segment_id, #{case_expression} as new_segment_id, x.balance_cents, x.person_type
        from (#{base_sql}) x
      SQL
    end

    private
      def detail_only? = @tenant.setting.detail_only?

      def base_sql
        <<~SQL
          select c.id as contract_id, c.segment_id as old_segment_id, c.broke_agreement,
                 agg.overdue_days, agg.balance as balance_cents, agg.overdue_bills,
                 case when agg.balance = 0 then 0 else agg.overdue_cents * 100.0 / agg.balance end as overdue_percent,
                 coalesce(p.customers, 0) as customers, (:today::date - #{BrDate.sql_date('c.created_at')}) as age_days,
                 p.person_type, #{keys_expression} as keys
          from (
            with considered as (
              select b.id, b.contract_id, b.due_date, greatest(b.amount_cents - b.paid_cents, 0) as balance, #{uses_products? ? folded('b.product') : 'null::text'} as product_key
              from bills b where b.tenant_id = #{@tenant.id.to_i} and b.status = 'active'#{detail_only? ? ' and b.due_date < :today::date' : ''}
            )
            select contract_id,
                   coalesce(max(:today::date - due_date) filter (where due_date < :today::date), 0) as overdue_days,
                   sum(balance) as balance,
                   count(*) filter (where due_date < :today::date) as overdue_bills,
                   coalesce(sum(balance) filter (where due_date < :today::date), 0) as overdue_cents,
                   #{aggregates_for_keys}
            from considered group by contract_id
          ) agg
          join contracts c on c.id = agg.contract_id
          #{uses_people? ? "left join (#{people_sql}) p on p.contract_id = c.id" : 'left join (select null::bigint as contract_id, null::bigint as customers, null::text as person_type where false) p on false'}
          #{product_join}
        SQL
      end

      # Só calcula o que algum segmento usa: produto (a agregação por título é a parte mais cara), tipo e número de clientes.
      def uses_products? = active_entries.any? { |entry| Array(entry[:products]).any? }
      def uses_people? = active_entries.any? { |entry| entry[:person_type].present? || entry[:min_customers].present? || entry[:max_customers].present? }
      def active_entries = @entries.select { |entry| entry[:active] && !entry[:catch_all] }

      # Agregados sem ordenação, para o PostgreSQL agrupar por hash (medido na V4: com `array_agg ... order by` ele escolheu agrupar pelo índice de
      # `bills (contract_id)` e levou 8 s; sem ordenação o agrupamento leva 0,5 s). O produto pelo título mais atrasado e pelo maior saldo saem
      # de subconsultas próprias com `distinct on`.
      def aggregates_for_keys
        return "'{}'::text[] as all_keys" unless uses_products? && @policy == "any_bill"

        "coalesce(array_agg(product_key) filter (where product_key is not null), '{}') as all_keys"
      end

      def keys_expression
        return "'{}'::text[]" unless uses_products?

        case @policy
        when "any_bill" then "agg.all_keys"
        when "largest_balance" then "case when big.product_key is null then '{}'::text[] else array[big.product_key] end"
        else "case when old.product_key is null then '{}'::text[] else array[old.product_key] end"
        end
      end

      def product_join
        return "" unless uses_products?

        case @policy
        when "largest_balance" then "left join (#{biggest_sql}) big on big.contract_id = c.id"
        when "any_bill" then ""
        else "left join (#{oldest_sql}) old on old.contract_id = c.id"
        end
      end

      def oldest_sql
        <<~SQL
          select distinct on (contract_id) contract_id, product_key from (
            select contract_id, due_date, id, #{folded('product')} as product_key
            from bills where tenant_id = #{@tenant.id.to_i} and status = 'active'#{detail_only? ? ' and due_date < :today::date' : ''}
          ) t where product_key is not null order by contract_id, due_date, id
        SQL
      end

      def biggest_sql
        <<~SQL
          select distinct on (contract_id) contract_id, product_key from (
            select contract_id, product_key, sum(greatest(amount_cents - paid_cents, 0)) as s
            from (select contract_id, amount_cents, paid_cents, #{folded('product')} as product_key from bills
                  where tenant_id = #{@tenant.id.to_i} and status = 'active'#{detail_only? ? ' and due_date < :today::date' : ''}) t
            where product_key is not null group by contract_id, product_key
          ) q order by contract_id, s desc, product_key
        SQL
      end

      def folded(column)
        "case when #{column} is null or btrim(#{column}) = '' then null else regexp_replace(translate(lower(btrim(#{column})), '#{ACCENTED}', '#{PLAIN}'), '\\s+', ' ', 'g') end"
      end

      # Tipo do contrato: o dos responsáveis financeiros; sem nenhum declarado, o dos titulares (MT-16, R9b); sem papel nenhum, o de todos.
      # Cliente anonimizado não conta para o tipo (o documento dele deixou de dizer PF ou PJ). Mais de um tipo é "misto". Mínimo e máximo do
      # texto dizem se há um tipo só (iguais) ou dois (diferentes), sem `count(distinct)`.
      def people_sql
        <<~SQL
          select contract_id, count(*) as customers,
                 case
                   when bool_or(fr) then case when min(kind) filter (where fr) is null then null when min(kind) filter (where fr) = max(kind) filter (where fr) then min(kind) filter (where fr) else 'mixed' end
                   when bool_or(h) then case when min(kind) filter (where h) is null then null when min(kind) filter (where h) = max(kind) filter (where h) then min(kind) filter (where h) else 'mixed' end
                   else case when min(kind) is null then null when min(kind) = max(kind) then min(kind) else 'mixed' end
                 end as person_type
          from (
            select cc.contract_id, jsonb_exists(cc.roles, 'financial_responsible') as fr, jsonb_exists(cc.roles, 'holder') as h,
                   case when cu.anonymized_at is not null then null when length(cu.document) = 11 then 'person' else 'company' end as kind
            from contract_customers cc join customers cu on cu.id = cc.customer_id
            where cu.tenant_id = #{@tenant.id.to_i}
          ) people
          group by contract_id
        SQL
      end

      def case_expression
        catch_all = @entries.find { |entry| entry[:catch_all] }
        whens = @entries.select { |entry| entry[:active] && !entry[:catch_all] }.map do |entry|
          "when #{conditions(entry)} then #{entry[:id].to_i}"
        end
        whens.empty? ? catch_all.fetch(:id).to_i.to_s : "case #{whens.join(' ')} else #{catch_all.fetch(:id).to_i} end"
      end

      def conditions(entry)
        parts = []
        Segment::RANGES.each do |range|
          column = range == :overdue_percent ? "x.overdue_percent" : "x.#{range}"
          column = "x.balance_cents" if range == :balance_cents
          low = entry[:"min_#{range}"]
          high = entry[:"max_#{range}"]
          parts << "#{column} >= #{Integer(low)}" if low.present?
          parts << "#{column} <= #{Integer(high)}" if high.present?
        end
        parts << "x.person_type = #{ActiveRecord::Base.connection.quote(entry[:person_type])}" if entry[:person_type].present?
        parts << (entry[:broke_agreement] == "yes" ? "x.broke_agreement" : "not x.broke_agreement") if entry[:broke_agreement].present?
        products = Array(entry[:products])
        parts << "x.keys && ARRAY[#{products.map { |product| ActiveRecord::Base.connection.quote(product) }.join(',')}]::text[]" if products.any?
        parts.empty? ? "true" : parts.join(" and ")
      end
  end
end
