module Portfolio
  # Consultas da carteira (R17 a R23), sempre limitadas aos credores em que o usuário pode consultar a carteira (MT-5). Situação
  # (vencido ou a vencer) e dias de atraso são calculados na consulta com a data de referência; nada disso é gravado (R6, R17).
  class Query
    SORTS = %w[name bills_count overdue_cents upcoming_cents max_days_overdue].freeze
    ACCENTED = "áàâãäéèêëíìîïóòôõöúùûüç".freeze
    PLAIN = "aaaaaeeeeiiiiooooouuuuc".freeze

    def initialize(user, reference: Date.current)
      @user = user
      @reference = reference
    end

    def tenant_ids = @user.tenant_ids_with("view_portfolio")

    # Lista de clientes (R21): valores, maior atraso e faixa. Sem busca, só quem tem título em cobrança (no modo "só na ficha", só
    # quem tem título vencido); com busca, qualquer cliente do credor. `bracket` é o índice da faixa pedida, ou -1 para "sem atraso".
    def customers(search: nil, bracket: nil, tenant_id: nil, sort: "overdue_cents", direction: "desc")
      ids = tenant_ids
      relation = Customer.visible_to(@user, "view_portfolio").joins("left join (#{aggregate_sql(ids)}) agg on agg.customer_id = customers.id")
        .select("customers.*", "coalesce(agg.bills_count, 0) as bills_count", "coalesce(agg.overdue_cents, 0) as overdue_cents",
                "coalesce(agg.upcoming_cents, 0) as upcoming_cents", "agg.max_days_overdue as max_days_overdue")
      relation = relation.where(tenant_id: tenant_id) if tenant_id.present? && ids.include?(tenant_id.to_i)
      relation = search.present? ? search_by(relation, search) : restrict_to_collection(relation, ids)
      relation = restrict_to_bracket(relation, ids, bracket) if bracket
      order(relation, sort, direction)
    end

    def settings_by_tenant(ids = tenant_ids) = TenantSetting.where(tenant_id: ids).index_by(&:tenant_id)

    # Faixa do cliente: a do título vencido mais atrasado (R19); "sem atraso" quando não há título vencido.
    def bracket_label(tenant_id, max_days_overdue)
      return "sem atraso" if max_days_overdue.nil? || max_days_overdue.to_i < 1

      @settings ||= settings_by_tenant
      brackets = AgingBrackets.from_stored(@settings.fetch(tenant_id).aging_brackets)
      brackets.label(brackets.index_for(max_days_overdue.to_i))
    end

    private
      def aggregate_sql(ids)
        ActiveRecord::Base.sanitize_sql_array([ <<~SQL, @reference, @reference, @reference, @reference, ids.presence || [ 0 ] ])
          select customer_id, count(*) as bills_count,
                 coalesce(sum(amount_cents - paid_cents) filter (where due_date < ?::date), 0) as overdue_cents,
                 coalesce(sum(amount_cents - paid_cents) filter (where due_date >= ?::date), 0) as upcoming_cents,
                 max(?::date - due_date) filter (where due_date < ?::date) as max_days_overdue
          from bills where status = 'active' and tenant_id in (?) group by customer_id
        SQL
      end

      def search_by(relation, search)
        term = FoldedText.fold(search)
        digits = search.gsub(/\D/, "")
        sql = "translate(lower(customers.name), '#{ACCENTED}', '#{PLAIN}') like :term"
        sql += " or customers.document like :digits" if digits.present?
        relation.where(sql, term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%", digits: "#{digits}%")
      end

      # Sem busca a lista mostra só quem está em cobrança; no modo "só na ficha", quem tem título vencido (R20, R21).
      def restrict_to_collection(relation, ids)
        detail_only = settings_by_tenant(ids).select { |_, setting| setting.detail_only? }.keys
        relation = relation.where("coalesce(agg.bills_count, 0) > 0")
        return relation if detail_only.empty?

        relation.where("customers.tenant_id not in (:ids) or coalesce(agg.overdue_cents, 0) > 0", ids: detail_only)
      end

      # Cada credor usa as próprias faixas (MT-7): a condição é montada por credor.
      def restrict_to_bracket(relation, ids, bracket)
        conditions = settings_by_tenant(ids).filter_map do |tenant_id, setting|
          brackets = AgingBrackets.from_stored(setting.aging_brackets)
          if bracket == -1
            ActiveRecord::Base.sanitize_sql_array([ "(customers.tenant_id = ? and agg.max_days_overdue is null)", tenant_id ])
          elsif brackets.brackets[bracket]
            ActiveRecord::Base.sanitize_sql_array([ "(customers.tenant_id = ? and #{brackets.sql_index('agg.max_days_overdue')} = ?)", tenant_id, bracket ])
          end
        end
        relation.where(conditions.any? ? conditions.join(" or ") : "false")
      end

      def order(relation, sort, direction)
        sort = SORTS.include?(sort) ? sort : "overdue_cents"
        direction = direction == "asc" ? "asc" : "desc"
        column = sort == "name" ? "customers.name" : sort
        relation.order(Arel.sql("#{column} #{direction} nulls last"), Arel.sql("customers.name asc"))
      end
  end
end
