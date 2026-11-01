module Segments
  # Traduz a árvore dos segmentos em consulta de conjunto por credor (decisão 0023, seção 3). Só fragmentos escritos aqui viram texto de
  # consulta; todo valor da árvore vai como parâmetro (`$n`), nunca concatenado. Cada tabela filha que alguma condição usa é lida uma vez,
  # agrupada por quem é dono dela (o sujeito, ou o cliente num papel do contrato), com uma coluna por condição (`count(*) filter (...)`,
  # `sum(...) filter (...)`); os atributos do contrato saem de uma base calculada uma vez e reaproveitada pelo sujeito e por "outros contratos".
  #
  # Três saídas: `classify` (o enquadramento: o primeiro item que casar, 13 R267), `probe` ("Conferir": o total e cada condição sozinha, R288)
  # e `matching` (os ids que casam, para o filtro da lista, R275).
  class Compiler
    Query = Data.define(:sql, :binds)

    ACCENTED = Portfolio::Query::ACCENTED
    PLAIN = Portfolio::Query::PLAIN
    SYMBOLS = { "eq" => "=", "ne" => "<>", "gt" => ">", "gte" => ">=", "lt" => "<", "lte" => "<=" }.freeze

    # Memória de ordenação e agrupamento das consultas da segmentação, só dentro da transação delas (`SET LOCAL`). O padrão do PostgreSQL (4 MB)
    # manda para o disco os agrupamentos de 200 mil contratos com dezenas de colunas; o valor e a medição estão no plano técnico da camada 17.
    WORK_MEM = "64MB"

    # Executa uma leitura da segmentação com a memória da consulta e os parâmetros.
    def self.select(query, timeout: nil)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("set local work_mem = '#{WORK_MEM}'")
        ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([ "set local statement_timeout = ?", timeout ])) if timeout
        ActiveRecord::Base.connection.select_all(query.sql, "Segments", query.binds).to_a
      end
    end

    def initialize(tenant, today: Date.current)
      @tenant = tenant
      @today = today
    end

    # Enquadramento: `entries` é a lista em ordem [[id do item, Expression], ...]; quem não casa fica com `default_id`. Só contratos com título em
    # cobrança entram (R267). Colunas: contract_id, tier_id, balance_cents, person_type.
    def classify(entries, default_id:)
      build("contracts") do |b|
        b.needs_people!
        whens = entries.map { |id, expression| "when #{b.expression(expression)} then #{Integer(id)}" }
        tier = whens.empty? ? Integer(default_id).to_s : "case #{whens.join(' ')} else #{Integer(default_id)} end"
        b.select("s.contract_id, #{tier} as tier_id, s.balance as balance_cents, s.person_type", where: "s.considered")
      end
    end

    # "Conferir" (R288): total, saldo e quantos pegaria cada condição sozinha, pelo endereço dela ("0", "4.1").
    def probe(expression)
      build(expression.subject) do |b|
        all = b.expression(expression)
        singles = expression.each_condition.map { |node, address| [ address, b.condition(node) ] }
        columns = [ "count(*) filter (where #{all}) as total", "coalesce(sum(s.balance) filter (where #{all}), 0) as balance" ]
        singles.each_with_index { |(_, sql), index| columns << "count(*) filter (where #{sql}) as c#{index}" }
        @probe_addresses = singles.map(&:first)
        b.select(columns.join(", "), group: true)
      end
    end

    attr_reader :probe_addresses

    # Os ids (de contrato ou de cliente, pelo sujeito) que casam: o filtro da lista avalia na hora (SG4).
    def matching(expression)
      build(expression.subject) do |b|
        b.select("s.#{expression.subject == 'customers' ? 'customer_id' : 'contract_id'} as id", where: b.expression(expression))
      end
    end

    private
      def build(subject)
        builder = Builder.new(@tenant, @today, subject)
        yield builder
        builder.query
      end

      # Monta uma consulta: guarda os parâmetros, as tabelas filhas por dono e o que a base precisa calcular.
      class Builder
        def initialize(tenant, today, subject)
          @tenant = tenant
          @subject = subject
          @binds = []
          @groups = {}
          @needs = Set.new
          @tenant_param = param(tenant.id, "bigint")
          @today_param = param(today.iso8601, "date")
          @detail_only = tenant.setting.detail_only?
        end

        def needs_people! = @needs << :people

        def select(columns, where: "true", group: false)
          @select = columns
          @where = where
          @aggregate = group
        end

        def query
          sql = +"with #{ctes.join(",\n")}\n"
          sql << "select #{@select}\nfrom #{@subject == 'customers' ? 'cu' : 'cb'} s\n"
          @groups.each_value { |group| sql << "left join (#{group.sql}) #{group.alias_name} on #{group.alias_name}.sid = s.#{owner_key}\n" }
          sql << "where #{@where}" unless @aggregate && @where == "true"
          Query.new(sql, @binds)
        end

        # A árvore inteira: as linhas soltas com "e", cada grupo com "ou" (R254).
        def expression(expression)
          parts = expression.conditions.map do |node|
            node.key?("any") ? "(#{Array(node['any']).map { |inner| condition(inner) }.join(' or ')})" : condition(node)
          end
          parts.empty? ? "true" : parts.join(" and ")
        end

        # Uma condição vira expressão sim/não, nunca nula; "não" a nega (R254).
        def condition(node)
          found = Catalog.resolve(@subject, node["path"])
          raise ArgumentError, "caminho fora do catálogo" unless found

          sql = found[:kind] == :attribute ? attribute(found, node) : collection(found, node)
          sql = "coalesce(#{sql}, false)"
          node["negate"] ? "(not #{sql})" : sql
        end

        def param(value, cast)
          @binds << ActiveRecord::Relation::QueryAttribute.new("p#{@binds.size + 1}", value, ActiveRecord::Type::Value.new)
          "$#{@binds.size}::#{cast}"
        end

        private
          def owner_key = @subject == "customers" ? "customer_id" : "contract_id"

          # Atributo do sujeito, ou de um cliente num papel do contrato ("algum titular com tipo = PJ", R257).
          def attribute(found, node)
            spec = found[:spec]
            if found[:parent]
              @needs << :customers
              column = Fields.customer(found[:name], "x")
              @needs << :customer_contracts if %w[overdue_days balance].include?(found[:name])
              return parent_attribute(found[:parent], compare(column, spec, node))
            end

            column = @subject == "customers" ? Fields.customer(found[:name], "s") : Fields.contract(found[:name], "s")
            note_contract_needs(found[:name]) if @subject == "contracts"
            @needs << :customer_contracts if @subject == "customers" && %w[overdue_days balance].include?(found[:name])
            compare(column, spec, node)
          end

          def parent_attribute(role, predicate)
            @needs << :roles
            group = (@groups[[ :parent_attribute, role ]] ||= Group.new("pa#{@groups.size}", "select r.contract_id as sid, %{columns} from roles r join cu x on x.customer_id = r.customer_id where #{Fields.role(role)} group by r.contract_id"))
            column = group.add("bool_or(coalesce(#{predicate}, false))")
            "#{group.alias_name}.#{column}"
          end

          def collection(found, node)
            name = found[:name]
            spec = found[:spec]
            note_collection_needs(name, node)
            return parent_collection(found, node) if found[:parent]

            group = (@groups[[ :collection, name ]] ||= Group.new("g#{@groups.size}", Sources.grouped(name, @subject == "customers" ? :customer : :contract, @tenant_param, @today_param)))
            boolean_over(group, spec, name, node) { |column, default| "coalesce(#{group.alias_name}.#{column}, #{default})" }
          end

          # Coleção de um cliente num papel: cada cliente é avaliado sozinho e o contrato casa se algum casar (R257). "Outros contratos" exclui o
          # contrato do sujeito (R263).
          def parent_collection(found, node)
            @needs << :roles
            role = found[:parent]
            name = found[:name]
            key = [ :parent_collection, role, name ]
            unless @groups[key]
              inner = name == "other_contracts" ? Sources.other_contracts(role) : Sources.grouped(name, :customer, @tenant_param, @today_param, key: "sid")
              join = name == "other_contracts" ? "(%{inner}) i" : "roles r left join (%{inner}) i on i.sid = r.customer_id"
              where = name == "other_contracts" ? "true" : Fields.role(role)
              @groups[key] = Group.new("pc#{@groups.size}", "select #{name == 'other_contracts' ? 'i.contract_id' : 'r.contract_id'} as sid, %{columns} from #{join} where #{where} group by 1", inner: inner)
            end
            group = @groups[key]
            predicate = boolean_over(group.inner_group, found[:spec], name, node) { |column, default| "coalesce(i.#{column}, #{default})" }
            column = group.add("bool_or(#{predicate})")
            "#{group.alias_name}.#{column}"
          end

          # As colunas agregadas da condição sobre a coleção e a expressão sim/não sobre elas (R254): quantidade, soma, maior e menor; algum,
          # todos e nenhum; janela de dias (R262) e qualificador (R258, R260).
          def boolean_over(group, spec, name, node)
            filter = [ Sources.qualifier(name, node["qualifier"], @today_param), window(name, node) ].compact
            if node["aggregate"].present?
              aggregate = node["aggregate"]
              value = aggregate == "count" ? "1" : Fields.item(name, node["field"], "x", @today_param)
              sql_aggregate = aggregate == "count" ? "count(*)" : "#{aggregate}(#{value})"
              column = group.add("#{sql_aggregate}#{filter_clause(filter)}")
              default = %w[count sum].include?(aggregate) ? "0" : "null"
              type = aggregate == "count" ? { type: :count } : spec[:fields].fetch(node["field"].to_sym)
              compare(yield(column, default), type, node)
            else
              item = node["where"].present? ? item_condition(name, spec, node["where"]) : nil
              matching = group.add("count(*)#{filter_clause(filter + [ item ].compact)}")
              case node["quantifier"]
              when "some" then "#{yield(matching, '0')} > 0"
              when "none" then "#{yield(matching, '0')} = 0"
              else
                total = group.add("count(*)#{filter_clause(filter)}")
                failing = group.add("count(*)#{filter_clause(filter + [ "not coalesce(#{item || 'true'}, false)" ])}")
                "(#{yield(total, '0')} > 0 and #{yield(failing, '0')} = 0)"
              end
            end
          end

          def item_condition(name, spec, where)
            field = where["field"]
            compare(Fields.item(name, field, "x", @today_param), spec[:fields].fetch(field.to_sym), where)
          end

          def window(name, node)
            days = node["within_days"]
            return nil if days.blank?

            "#{Sources.date_of(name)} >= (#{@today_param} - #{param(Integer(days), 'integer')})"
          end

          def filter_clause(parts) = parts.empty? ? "" : " filter (where #{parts.join(' and ')})"

          # Comparação com parâmetro (R254): número, opção, referência e texto (texto sem acento e sem maiúsculas, como a 08 fazia com o produto).
          def compare(column, spec, node)
            op = node["op"]
            return "#{column} is true" if spec[:type] == :boolean

            if op == "between"
              low, high = node["value"]
              return "#{column} between #{value_param(low, spec)} and #{value_param(high, spec)}"
            end
            return "#{column} = any(array[#{Array(node['value']).map { |item| value_param(item, spec) }.join(', ')}])" if op == "in"

            sql_op = SYMBOLS.fetch(op)
            sql_op == "<>" ? "#{column} is distinct from #{value_param(node['value'], spec)}" : "#{column} #{sql_op} #{value_param(node['value'], spec)}"
          end

          def value_param(value, spec)
            case spec[:type]
            when :text then param(FoldedText.fold(value), "text")
            when :option then param(value.to_s, "text")
            when :reference then param(Integer(value), "bigint")
            else param(Integer(value), "numeric")
            end
          end

          def note_contract_needs(name)
            @needs << :people if %w[person_type].include?(name)
            @needs << :product if name == "product"
            @needs << :product_largest if name == "product_largest"
            @needs << :updated if name == "updated_value"
          end

          def note_collection_needs(name, node)
            @needs << :customers if name == "customers"
            @needs << :customers if @subject == "customers"
            fields = [ node["field"], node.dig("where", "field") ].compact
            fields.each { |field| note_contract_needs(field) } if %w[contracts other_contracts].include?(name)
          end

          def ctes
            list = [ "cb as (#{Bases.contracts(@needs, @tenant_param, @today_param, @detail_only)})" ]
            list << "cu as (#{Bases.customers(@needs, @tenant_param, @today_param)})" if @subject == "customers" || @needs.include?(:customers) || @needs.include?(:roles)
            list << "roles as (#{Bases.roles(@tenant_param)})" if @needs.include?(:roles)
            list
          end
      end

      # Uma subconsulta agrupada por dono, com as colunas que as condições acrescentam (`m0`, `m1`...).
      class Group
        attr_reader :alias_name, :inner_group

        def initialize(alias_name, template, inner: nil)
          @alias_name = alias_name
          @template = template
          @columns = []
          @inner_group = inner && Group.new("i", inner)
        end

        def add(sql)
          @columns << sql
          "m#{@columns.size - 1}"
        end

        def sql
          columns = @columns.each_with_index.map { |column, index| "#{column} as m#{index}" }.join(", ")
          @inner_group ? format(@template, columns: columns, inner: @inner_group.sql) : format(@template, columns: columns)
        end
      end

      # Expressões de campo por coleção e atributo (R255 a R261). Nenhuma recebe texto do usuário.
      module Fields
        module_function

        def folded(column)
          "case when #{column} is null or btrim(#{column}) = '' then null else regexp_replace(translate(lower(btrim(#{column})), '#{ACCENTED}', '#{PLAIN}'), '\\s+', ' ', 'g') end"
        end

        CONTRACT = %w[overdue_days balance overdue_percent age_days person_type product product_largest broke_agreement in_arrears updated_value].freeze
        CUSTOMER = %w[person_type customer_days overdue_days balance].freeze

        def contract(name, table)
          raise ArgumentError, name unless CONTRACT.include?(name.to_s)

          "#{table}.#{name}"
        end

        def customer(name, table)
          raise ArgumentError, name unless CUSTOMER.include?(name.to_s)

          "#{table}.#{name}"
        end

        # Campo de um item da coleção, sobre o apelido `x` da fonte.
        def item(collection, field, table, today)
          case [ collection.to_s, field.to_s ]
          in [ "bills", "overdue_days" ] then "greatest(#{today} - #{table}.due_date, 0)"
          in [ "bills", "balance" ] then "greatest(#{table}.amount_cents - #{table}.paid_cents, 0)"
          in [ "bills", "amount" ] then "#{table}.amount_cents"
          in [ "bills", "product" ] then "#{table}.product_key"
          in [ "bills", "kind" ] then "#{table}.kind"
          in [ "contact_attempts", "result" ] then "#{table}.result_id"
          in [ "contact_attempts", "result_kind" ] then "#{table}.result_kind"
          in [ "contact_attempts", "channel" ] then "#{table}.channel"
          in [ "contacts", "status" | "kind" | "origin" ] then "#{table}.#{field}"
          in [ "contacts", "state" ] then folded("#{table}.state")
          in [ "contacts", "city" ] then folded("#{table}.city")
          in [ "promises", "state" ] then "#{table}.state"
          in [ "agreements", "state" | "mode" ] then "#{table}.#{field}"
          in [ "payments", "method" ] then "#{table}.payment_method"
          in [ "payments", "amount" ] then "#{table}.amount_cents"
          in [ "contracts" | "other_contracts", _ ] then contract(field, table)
          in [ "customers", "person_type" ] then "#{table}.person_type"
          end
        end

        # Quem é cliente no papel (R257, MT-16): titular é quem tem o papel (ou nenhum papel, que vale os dois); responsável financeiro é quem tem o
        # papel e, sem nenhum declarado no contrato, os titulares; "cliente" é qualquer um.
        def role(role)
          case role
          when "holder" then "r.is_holder"
          when "responsible" then "(r.is_fr or (not r.has_fr and r.is_holder))"
          else "true"
          end
        end
      end

      # De onde vem cada coleção e como se liga ao dono (R258 a R261). Toda fonte filtra pelo credor.
      module Sources
        module_function

        def grouped(name, owner, tenant, today, key: "sid")
          from, owner_column = source(name, owner, tenant)
          "select #{owner_column} as #{key}, %{columns} #{from} group by 1"
        end

        def source(name, owner, tenant)
          contract = owner == :contract
          case name.to_s
          when "bills"
            contract ? [ "from bills x where x.tenant_id = #{tenant}", "x.contract_id" ] : [ "from bills x join contract_customers k on k.contract_id = x.contract_id where x.tenant_id = #{tenant}", "k.customer_id" ]
          when "contact_attempts"
            contract ? [ "from contact_attempts x where x.tenant_id = #{tenant} and x.contract_id is not null", "x.contract_id" ] : [ "from contact_attempts x where x.tenant_id = #{tenant}", "x.customer_id" ]
          when "contacts"
            contract ? [ "from customer_contacts x join contract_customers k on k.customer_id = x.customer_id where x.tenant_id = #{tenant}", "k.contract_id" ] : [ "from customer_contacts x where x.tenant_id = #{tenant}", "x.customer_id" ]
          when "promises"
            [ "from payment_promises x where x.tenant_id = #{tenant}", contract ? "x.contract_id" : "x.customer_id" ]
          when "agreements"
            contract ? [ "from (select distinct ab.contract_id as owner_id, a.* from agreement_bills ab join agreements a on a.id = ab.agreement_id where a.tenant_id = #{tenant}) x", "x.owner_id" ] : [ "from agreements x where x.tenant_id = #{tenant}", "x.customer_id" ]
          when "payments"
            contract ? [ "from payments x join bills b on b.id = x.bill_id where x.tenant_id = #{tenant} and x.status = 'applied'", "b.contract_id" ] : [ "from payments x join bills b on b.id = x.bill_id join contract_customers k on k.contract_id = b.contract_id where x.tenant_id = #{tenant} and x.status = 'applied'", "k.customer_id" ]
          when "contracts"
            [ "from contract_customers k join cb x on x.contract_id = k.contract_id", "k.customer_id" ]
          when "customers"
            [ "from contract_customers k join cu x on x.customer_id = k.customer_id", "k.contract_id" ]
          end
        end

        # Outros contratos do cliente no papel, sem o contrato do sujeito: um grupo por contrato do sujeito e cliente.
        def other_contracts(role)
          "select r.contract_id, %{columns} from roles r join contract_customers k on k.customer_id = r.customer_id and k.contract_id <> r.contract_id " \
            "join cb x on x.contract_id = k.contract_id where #{Fields.role(role)} group by r.contract_id, r.customer_id"
        end

        # Título em aberto (SG12) é o título com saldo a pagar, vencido ou a vencer; os qualificadores recortam (R258).
        def qualifier(name, qualifier, today)
          case name.to_s
          when "bills"
            case qualifier
            when "overdue" then "x.status = 'active' and x.due_date < #{today}"
            when "due" then "x.status = 'active' and x.due_date >= #{today}"
            when "paid", "withdrawn", "renegotiated" then "x.status = '#{qualifier}'"
            else "x.status = 'active'"
            end
          when "contacts" then Catalog::CONTACT_STATUSES.include?(qualifier) ? "x.status = '#{qualifier}'" : nil
          when "contracts", "other_contracts" then qualifier == "in_arrears" ? "x.in_arrears" : nil
          end
        end

        def date_of(name)
          case name.to_s
          when "contact_attempts" then BrDate.sql_date("x.contacted_at")
          when "promises" then BrDate.sql_date("x.created_at")
          when "agreements" then BrDate.sql_date("x.effectuated_at")
          when "payments" then "x.paid_on"
          end
        end
      end

      # As bases: atributos do contrato (08, R150) e do cliente, e os papéis dos clientes no contrato.
      module Bases
        module_function

        def contracts(needs, tenant, today, detail_only)
          considered = "b.tenant_id = #{tenant} and b.status = 'active'#{detail_only ? " and b.due_date < #{today}" : ''}"
          people = needs.include?(:people)
          <<~SQL
            select c.id as contract_id, c.broke_agreement,
                   coalesce(agg.overdue_days, 0) as overdue_days, coalesce(agg.balance, 0) as balance,
                   case when coalesce(agg.balance, 0) = 0 then 0 else agg.overdue_cents * 100.0 / agg.balance end as overdue_percent,
                   (#{today} - #{BrDate.sql_date('c.created_at')}) as age_days,
                   agg.contract_id is not null as considered, coalesce(agg.overdue_bills, 0) > 0 as in_arrears,
                   #{people ? 'p.person_type' : 'null::text as person_type'},
                   #{needs.include?(:product) ? 'old.product_key' : 'null::text'} as product,
                   #{needs.include?(:product_largest) ? 'big.product_key' : 'null::text'} as product_largest,
                   #{needs.include?(:updated) ? 'coalesce(upd.total, 0)' : '0::bigint'} as updated_value
            from contracts c
            left join (
              select b.contract_id,
                     coalesce(max(#{today} - b.due_date) filter (where b.due_date < #{today}), 0) as overdue_days,
                     sum(greatest(b.amount_cents - b.paid_cents, 0)) as balance,
                     count(*) filter (where b.due_date < #{today}) as overdue_bills,
                     coalesce(sum(greatest(b.amount_cents - b.paid_cents, 0)) filter (where b.due_date < #{today}), 0) as overdue_cents
              from bills b where #{considered} group by b.contract_id
            ) agg on agg.contract_id = c.id
            #{people ? "left join (#{people_sql(tenant)}) p on p.contract_id = c.id" : ''}
            #{needs.include?(:product) ? "left join (#{oldest_sql(considered)}) old on old.contract_id = c.id" : ''}
            #{needs.include?(:product_largest) ? "left join (#{biggest_sql(considered)}) big on big.contract_id = c.id" : ''}
            #{needs.include?(:updated) ? "left join (select b.contract_id, sum(v.total_cents) as total from bill_valuations v join bills b on b.id = v.bill_id where #{considered} group by b.contract_id) upd on upd.contract_id = c.id" : ''}
            where c.tenant_id = #{tenant}
          SQL
        end

        # Produto pelo título mais atrasado com produto e pelo maior saldo somado (08, R150 e revisão 1), em subconsultas com `distinct on`
        # (medido na camada 12: agregação ordenada dentro do `group by` custava 10 s com 200 mil contratos).
        def oldest_sql(considered)
          "select distinct on (contract_id) contract_id, product_key from (select b.contract_id, b.due_date, b.id, b.product_key " \
            "from bills b where #{considered}) t where product_key is not null order by contract_id, due_date, id"
        end

        def biggest_sql(considered)
          "select distinct on (contract_id) contract_id, product_key from (select contract_id, product_key, sum(balance) as s from (select b.contract_id, " \
            "greatest(b.amount_cents - b.paid_cents, 0) as balance, b.product_key from bills b where #{considered}) t " \
            "where product_key is not null group by contract_id, product_key) q order by contract_id, s desc, product_key"
        end

        # Tipo do contrato: o dos responsáveis financeiros; sem nenhum, o dos titulares; sem papel, o de todos (MT-16). Anonimizado não conta.
        def people_sql(tenant)
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
              from contract_customers cc join customers cu on cu.id = cc.customer_id where cu.tenant_id = #{tenant}
            ) people group by contract_id
          SQL
        end

        def customers(needs, tenant, today)
          contracts = needs.include?(:customer_contracts)
          <<~SQL
            select cu.id as customer_id,
                   case when cu.anonymized_at is not null then null when length(cu.document) = 11 then 'person' else 'company' end as person_type,
                   (#{today} - #{BrDate.sql_date('cu.created_at')}) as customer_days,
                   #{contracts ? 'coalesce(k.overdue_days, 0)' : '0'} as overdue_days, #{contracts ? 'coalesce(k.balance, 0)' : '0'} as balance
            from customers cu
            #{contracts ? 'left join (select cc.customer_id, max(cb.overdue_days) as overdue_days, sum(cb.balance) as balance from contract_customers cc join cb on cb.contract_id = cc.contract_id group by 1) k on k.customer_id = cu.id' : ''}
            where cu.tenant_id = #{tenant}
          SQL
        end

        def roles(tenant)
          <<~SQL
            select cc.contract_id, cc.customer_id,
                   (jsonb_exists(cc.roles, 'holder') or cc.roles = '[]'::jsonb) as is_holder,
                   jsonb_exists(cc.roles, 'financial_responsible') as is_fr,
                   bool_or(jsonb_exists(cc.roles, 'financial_responsible')) over (partition by cc.contract_id) as has_fr
            from contract_customers cc join contracts c on c.id = cc.contract_id where c.tenant_id = #{tenant}
          SQL
        end
      end
  end
end
