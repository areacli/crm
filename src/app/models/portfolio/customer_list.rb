module Portfolio
  # A lista de clientes (R21) com 200 mil clientes: a relação com os filtros, o total sem agregar e a página sem juntar a carteira inteira (plano técnico
  # da lista de clientes com 200 mil, decisão 0010). `scope` traz os filtros que olham o cliente; os que olham os títulos ficam no agregado.
  class CustomerList
    AGGREGATE_SORTS = %w[bills_count overdue_cents upcoming_cents max_days_overdue].freeze
    SELECT = [ "customers.*", "coalesce(agg.bills_count, 0) as bills_count", "coalesce(agg.overdue_cents, 0) as overdue_cents",
               "coalesce(agg.upcoming_cents, 0) as upcoming_cents", "agg.max_days_overdue as max_days_overdue" ].freeze

    # `narrowed`: fora da busca, o `scope` tem algum filtro além do credor. `search`: há busca, e aí entra também o cliente sem título em cobrança (R21).
    def initialize(scope, reference:, tenant_ids:, settings:, narrowed:, search:, bracket:, sort:, direction:)
      @scope = scope
      @reference = reference
      @tenant_ids = tenant_ids.presence || [ 0 ]
      @settings = settings
      @narrowed = narrowed
      @search = search
      @bracket = bracket
      @sort = sort
      @direction = direction
    end

    def relation = @relation ||= build(@scope, narrowed: @narrowed)

    # Só a faixa precisa da agregação. O resto conta clientes: quem tem título em cobrança é um `exists`, sem somar nada. Consulta: `bills (customer_id)`.
    def total
      return relation.except(:select, :order).count if @bracket

      (@search ? @scope : @scope.where(in_collection_sql)).count
    end

    # A página, sem juntar a carteira inteira a `customers` para ordenar. A busca já restringiu quem é agregado; com a faixa, a ordem por nome precisa do agregado.
    def records(limit:, offset:)
      return relation.limit(limit).offset(offset) if @search || (@sort == "name" && @bracket)
      return name_page(limit, offset) if @sort == "name"

      value_page(limit, offset)
    end

    private
      # Na busca, o agregado é calculado cliente a cliente, só para quem casou: com o RLS da operação o planejador erra a estimativa do agregado por conjunto (3,8 s contra 0,2 s, no
      # plano técnico). Fora dela, com filtro no cliente, `alvo` aparece duas vezes (na lista e no agregado): o PostgreSQL a materializa e avalia o filtro uma vez só.
      def build(scope, narrowed:)
        return ordered(scope.joins("join lateral (#{per_customer_sql}) agg on true").select(*SELECT).then { |list| @bracket ? list.where(bracket_condition) : list }) if @search

        base = narrowed ? Customer.with(alvo: scope.select(:id)).where("customers.id in (select id from alvo)") : scope
        ordered(base.with(agg: Arel.sql(aggregate_sql(narrowed))).joins("inner join agg on agg.customer_id = customers.id").select(*SELECT))
      end

      # Ordem por valor do agregado: `corte` acha no agregado o valor do último cliente da página, e só quem chega até ele é juntado a `customers` e ordenado com o desempate pelo
      # nome. O empate no corte entra inteiro. `corte` vazio ou nulo (a página passa do fim, ou cai nos clientes sem atraso) não restringe. Todo título visível tem o cliente
      # visível (`Operations::ReachBuilder`), por isso o corte vale também para a operação.
      def value_page(limit, offset)
        relation.with(corte: Arel.sql("select #{@sort} as valor from agg order by #{@sort} #{@direction} nulls last limit 1 offset #{offset + limit - 1}"))
          .where("agg.#{@sort} #{@direction == 'asc' ? '<=' : '>='} (select valor from corte) or (select valor from corte) is null")
          .limit(limit).offset(offset)
      end

      # Ordem por nome: os clientes da página saem de `customers`, e só eles são agregados.
      def name_page(limit, offset)
        build(@scope.where(in_collection_sql).order(name: @direction).limit(limit).offset(offset), narrowed: true)
      end

      def columns_sql
        ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, @reference, @reference, @reference, @reference ])
          count(*) as bills_count,
          coalesce(sum(greatest(amount_cents - paid_cents, 0)) filter (where due_date < ?::date), 0) as overdue_cents,
          coalesce(sum(greatest(amount_cents - paid_cents, 0)) filter (where due_date >= ?::date), 0) as upcoming_cents,
          max(?::date - due_date) filter (where due_date < ?::date) as max_days_overdue
        SQL
      end

      def active_bills_sql = ActiveRecord::Base.sanitize_sql_array([ "from bills where status = 'active' and tenant_id in (?)", @tenant_ids ])

      # Sem `group by`, sempre uma linha: o cliente sem título em cobrança aparece na busca com tudo zerado (R21). Consulta: `bills (customer_id)`.
      def per_customer_sql = "select #{columns_sql} #{active_bills_sql} and customer_id = customers.id"

      def aggregate_sql(narrowed)
        among = narrowed ? "and customer_id in (select id from alvo)" : ""
        aggregate = "select tenant_id, customer_id, #{columns_sql} #{active_bills_sql} #{among} group by tenant_id, customer_id"
        conditions = [ detail_only_condition, (bracket_condition("agg.tenant_id") if @bracket) ].compact
        conditions.empty? ? aggregate : "select * from (#{aggregate}) agg where (#{conditions.join(') and (')})"
      end

      # No modo "só na ficha", a lista traz só quem tem título vencido (R20, R21).
      def detail_only_tenants = @settings.select { |_, setting| setting.detail_only? }.keys

      def detail_only_condition
        return if detail_only_tenants.empty?

        ActiveRecord::Base.sanitize_sql_array([ "agg.tenant_id not in (?) or agg.overdue_cents > 0", detail_only_tenants ])
      end

      def in_collection_sql
        overdue = detail_only_tenants.empty? ? "" : ActiveRecord::Base.sanitize_sql_array([ "and (b.tenant_id not in (?) or (b.due_date < ?::date and b.amount_cents > b.paid_cents))", detail_only_tenants, @reference ])
        ActiveRecord::Base.sanitize_sql_array([ "exists (select 1 from bills b where b.customer_id = customers.id and b.status = 'active' and b.tenant_id in (?) #{overdue})", @tenant_ids ])
      end

      # Cada credor usa as próprias faixas (MT-7): a condição é montada por credor. `-1` é "sem atraso".
      def bracket_condition(tenant_column = "customers.tenant_id")
        conditions = @settings.filter_map do |tenant_id, setting|
          brackets = AgingBrackets.from_stored(setting.aging_brackets)
          if @bracket == -1
            ActiveRecord::Base.sanitize_sql_array([ "(#{tenant_column} = ? and agg.max_days_overdue is null)", tenant_id ])
          elsif brackets.brackets[@bracket]
            ActiveRecord::Base.sanitize_sql_array([ "(#{tenant_column} = ? and #{brackets.sql_index('agg.max_days_overdue')} = ?)", tenant_id, @bracket ])
          end
        end
        conditions.any? ? conditions.join(" or ") : "false"
      end

      def ordered(list)
        column = @sort == "name" ? "customers.name" : @sort
        list.order(Arel.sql("#{column} #{@direction} nulls last"), Arel.sql("customers.name asc"))
      end
  end
end
