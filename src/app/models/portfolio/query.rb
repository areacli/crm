module Portfolio
  # Consultas da carteira (R17 a R23), sempre limitadas aos credores em que o usuário pode consultar a carteira (MT-5). Situação
  # (vencido ou a vencer) e dias de atraso são calculados na consulta com a data de referência; nada disso é gravado (R6, R17).
  class Query
    # Filtro "Promessa" da lista (10, R204): olha as promessas feitas pelo cliente da linha. Consulta: `payment_promises (customer_id)`.
    PROMISE_FILTERS = %w[open pending broken none].freeze
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
    def customers(**filters) = customer_list(**filters).relation

    # A mesma lista, para a grade: sabe contar e paginar sem agregar a carteira a cada passo (`CustomerList`).
    def customer_list(search: nil, bracket: nil, segment: nil, tenant_id: nil, sort: "overdue_cents", direction: "desc", promise: nil, unrecognized_city: nil)
      ids = tenant_ids
      ids = [ tenant_id.to_i ] if tenant_id.present? && ids.include?(tenant_id.to_i)
      scope = Customer.visible_to(@user, "view_portfolio").where(tenant_id: ids)
      scope = search_by(scope, search, ids) if search.present?
      scope = restrict_to_segment(scope, ids, segment) if segment.present?
      scope = restrict_to_promise(scope, promise) if PROMISE_FILTERS.include?(promise.to_s)
      # 11, R243, AB9: o cliente cujo endereço válido mais recente não casa com a lista de municípios do IBGE (ou que não tem endereço).
      scope = scope.where(Agreements::Square::UNRECOGNIZED_SQL) if unrecognized_city.to_s == "1"
      CustomerList.new(scope, reference: @reference, tenant_ids: ids, settings: settings_by_tenant(ids), bracket: bracket, search: search.present?,
                       narrowed: segment.present? || PROMISE_FILTERS.include?(promise.to_s) || unrecognized_city.to_s == "1",
                       sort: SORTS.include?(sort) ? sort : "overdue_cents", direction: direction == "asc" ? "asc" : "desc")
    end

    def settings_by_tenant(ids = tenant_ids) = TenantSetting.where(tenant_id: ids).index_by(&:tenant_id)

    # Faixa do cliente: a do título vencido mais atrasado (R19); "sem atraso" quando não há título vencido.
    def bracket_label(tenant_id, max_days_overdue)
      return "sem atraso" if max_days_overdue.nil? || max_days_overdue.to_i < 1

      @settings ||= settings_by_tenant
      brackets = AgingBrackets.from_stored(@settings.fetch(tenant_id).aging_brackets)
      brackets.label(brackets.index_for(max_days_overdue.to_i))
    end

    # Enquadramento financeiro do contrato mais atrasado de cada cliente da página (13, R275, R296); empate no atraso, o de maior saldo (P-S3). Uma consulta para os (até 100)
    # clientes mostrados, e não uma subconsulta na lista inteira: a medição com 200 mil clientes mostrou 7,6 s contra 0,1 s. Índices:
    # `contract_customers (customer_id)` e `bills (contract_id)`.
    def tier_names(customer_ids)
      return {} if customer_ids.empty?

      rows = Portfolio::Sql.rows(<<~SQL, @reference, @reference, customer_ids)
        select distinct on (cc.customer_id) cc.customer_id, case when s.catch_all then null else g.name end as name
        from contract_customers cc
        join contracts c on c.id = cc.contract_id and c.tier_id is not null
        join tiers s on s.id = c.tier_id
        left join segments g on g.id = s.segment_id
        left join lateral (
          select max(?::date - b.due_date) filter (where b.due_date < ?::date) as days, sum(greatest(b.amount_cents - b.paid_cents, 0)) as balance
          from bills b where b.contract_id = c.id and b.status = 'active'
        ) late on true
        where cc.customer_id in (?)
        order by cc.customer_id, late.days desc nulls last, late.balance desc nulls last, c.id
      SQL
      rows.to_h { |row| [ row["customer_id"].to_i, row["name"] || I18n.t("tiers.catch_all") ] }
    end

    # Valor atualizado dos títulos vencidos de cada cliente da página (09, R175): lido de `bill_valuations` só para os (até 100) clientes mostrados, depois da
    # paginação, sem mexer na consulta principal da lista. Consulta: `bills (customer_id, number)` e a chave de `bill_valuations`. A lista não traz total.
    def updated_totals(customer_ids)
      return {} if customer_ids.empty?

      Portfolio::Sql.rows("select b.customer_id, sum(v.total_cents)::bigint as cents from bill_valuations v join bills b on b.id = v.bill_id where b.customer_id in (?) group by 1",
                          customer_ids).to_h { |row| [ row["customer_id"].to_i, row["cents"].to_i ] }
    end

    # Segmentos que o usuário pode escolher no filtro: os ativos dos credores em que consulta, de clientes e de contratos (13, R275).
    def segment_options(ids = tenant_ids) = Segment.where(tenant_id: ids, active: true).includes(:tenant).order(:subject, :name_key).to_a

    # O segmento escolhido passou do tempo da lista (2 s): a lista diz que ele demora demais para ela (13, revisão 3).
    def segment_too_slow? = @segment_too_slow == true

    private
      def restrict_to_promise(relation, filter)
        case filter
        when "open", "pending" then relation.where("exists (select 1 from payment_promises pp where pp.customer_id = customers.id and pp.state = ?)", filter)
        when "broken" then relation.where("exists (select 1 from payment_promises pp where pp.customer_id = customers.id and pp.state = 'broken' and pp.closed_at >= ?)", 30.days.ago)
        else relation.where("not exists (select 1 from payment_promises pp where pp.customer_id = customers.id and pp.state in ('open', 'pending'))")
        end
      end

      # Filtro por segmento (13, R275): segmento de clientes casa com o cliente; de contratos, com o cliente que tem algum contrato que casa. Avaliado
      # na hora (SG4), com 2 s de limite; os clientes que casam vão para uma tabela temporária da conexão, e a lista a lê (valor nenhum da árvore
      # entra no texto da consulta, decisão 0023).
      def restrict_to_segment(relation, ids, segment_id)
        segment = Segment.find_by(tenant_id: ids, id: segment_id.to_i)
        return relation.where("false") unless segment

        loaded = Segments::ListFilter.load(segment)
        @segment_too_slow = !loaded
        loaded ? relation.where("customers.id in (select customer_id from #{Segments::ListFilter::TABLE})") : relation.where("false")
      end

      # 17, R424: o texto inteiro é procurado antes como id remoto de cliente, por igualdade exata (SI2), pelo índice
      # `customer_identities (tenant_id, external_id, source_system_id)`. Se for o id de alguém, a lista fica só com os donos dele, pela chave primária; se não
      # for, a busca por nome e documento é a de antes. Sem `OR` entre as duas: o plano da lista de 200 mil clientes, ajustado em 08/11/2026, não muda.
      def search_by(relation, search, tenant_ids)
        identified = CustomerIdentity.where(tenant_id: tenant_ids, external_id: search.strip).distinct.pluck(:customer_id)
        return relation.where(id: identified) if identified.any?

        term = FoldedText.fold(search)
        digits = search.gsub(/\D/, "")
        sql = "translate(lower(customers.name), '#{ACCENTED}', '#{PLAIN}') like :term"
        sql += " or customers.document like :digits" if digits.present?
        relation.where(sql, term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%", digits: "#{digits}%")
      end
  end
end
