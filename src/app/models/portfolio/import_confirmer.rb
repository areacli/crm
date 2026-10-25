module Portfolio
  # Confirmação da importação (R10): grava só as linhas válidas, numa única transação, em SQL em lote (decisão 0004). Clientes,
  # contratos, títulos, retiradas e o histórico de alterações saem da tabela de preparação; nada é gravado se qualquer passo falhar.
  class ImportConfirmer
    # Papéis de um cliente que entra num contrato: nascem vazios e são preenchidos, em seguida, pelos papéis declarados nas linhas
    # da planilha (R9b); coluna `papel` vazia vale os dois papéis.
    NO_ROLES = "[]".freeze
    TEMPORARY_TABLES = %w[import_customers import_omission import_bills import_withdrawn].freeze

    def run(import)
      import.update!(status: :confirming, progress_percent: 1, progress_label: "Gravando a carteira")
      begin
        ApplicationRecord.transaction do
          # Uma importação por vez por credor (R10, caso de exceção): bloqueio consultivo da transação.
          Sql.execute("select pg_advisory_xact_lock(1, ?)", import.tenant_id)
          write(import)
        end
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { import_id: import.id })
        # Nada foi gravado (transação desfeita). O tipo do erro fica na execução; o detalhe, no registro.
        import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
        return
      end
      # Carga em massa deixa as estatísticas defasadas (o autovacuum demora): sem isto, a primeira consulta depois da carga pega um plano ruim.
      %w[customers contracts contract_customers bills].each { |table| Sql.connection.execute("analyze #{table}") }
      Sql.run("delete from import_rows where import_id = ?", import.id)
      FileUtils.rm_f(import.file_path) if import.stored_path
      import.update!(status: :confirmed, progress_percent: 100, progress_label: nil, finished_at: Time.current)
    end

    private
      def write(import)
        t = import.tenant_id
        i = import.id
        u = import.user_id
        # As tabelas temporárias somem no fim da transação; o descarte explícito cobre a transação aninhada (como nos testes).
        TEMPORARY_TABLES.each { |name| Sql.connection.execute("drop table if exists #{name}") }

        # Uma linha por cliente: nome, telefone e e-mail da última linha válida do documento.
        Sql.run(<<~SQL, i)
          create temporary table import_customers on commit drop as
          select distinct on (document) document, name, phone, email from import_rows where import_id = ? and ok order by document, line desc
        SQL
        Sql.connection.execute("analyze import_customers")
        # R8: a mudança de nome, telefone ou e-mail fica registrada; contato vazio na carga nova não apaga o anterior.
        %w[name phone email].each do |field|
          guard = field == "name" ? "" : "and new.#{field} is not null"
          Sql.run(<<~SQL, t, u, i, t)
            insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
            select ?, ?, ?, 'customer', c.id, 'updated', '#{field}', c.#{field}, new.#{field}, now()
            from import_customers new join customers c on c.tenant_id = ? and c.document = new.document
            where c.#{field} is distinct from new.#{field} #{guard}
          SQL
        end
        Sql.run(<<~SQL, t)
          insert into customers (tenant_id, document, name, phone, email, created_at, updated_at)
          select ?, document, name, phone, email, now(), now() from import_customers
          on conflict (tenant_id, document) do update set
            name = excluded.name, phone = coalesce(excluded.phone, customers.phone), email = coalesce(excluded.email, customers.email), updated_at = now()
        SQL
        # Contratos declarados na planilha (MT-14).
        Sql.run(<<~SQL, t, i)
          insert into contracts (tenant_id, code, created_by_omission, created_at, updated_at)
          select distinct ?, contract, false, now(), now() from import_rows where import_id = ? and ok and contract is not null
          on conflict (tenant_id, code) where code is not null do nothing
        SQL
        # Contrato por omissão: um por cliente, reaproveitado nas cargas seguintes.
        Sql.run(<<~SQL, t, t, i, t)
          insert into contracts (tenant_id, code, created_by_omission, created_at, updated_at)
          select ?, null, true, now(), now() from (
            select distinct c.id from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
            where r.import_id = ? and r.ok and r.contract is null
              and not exists (select 1 from contract_customers cc join contracts k on k.id = cc.contract_id
                              where cc.customer_id = c.id and k.created_by_omission and k.tenant_id = ?)) need
        SQL
        # O insert acima não sabe a qual cliente cada contrato novo pertence: liga pela ordem.
        link_omission_contracts(t, i)
        # Clientes de cada contrato declarado, com os papéis padrão.
        Sql.run(<<~SQL, NO_ROLES, t, t, i)
          insert into contract_customers (contract_id, customer_id, roles)
          select distinct k.id, c.id, ?::jsonb
          from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
          join contracts k on k.tenant_id = ? and k.code = r.contract
          where r.import_id = ? and r.ok
          on conflict (contract_id, customer_id) do nothing
        SQL
        # Contrato de cada linha: o declarado ou o de omissão do cliente (dois caminhos separados, e não uma junção lateral).
        Sql.run(<<~SQL, t)
          create temporary table import_omission on commit drop as
          select distinct on (cc.customer_id) cc.customer_id, k.id as contract_id
          from contract_customers cc join contracts k on k.id = cc.contract_id
          where k.tenant_id = ? and k.created_by_omission order by cc.customer_id, k.id
        SQL
        Sql.connection.execute("create index on import_omission (customer_id)")
        Sql.connection.execute("analyze import_omission")
        Sql.run(<<~SQL, t, t, i, t, i)
          create temporary table import_bills on commit drop as
          select r.line, r.number, r.due_date, r.amount_cents, r.description, r.roles, c.id as customer_id, k.id as contract_id
          from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
          join contracts k on k.tenant_id = ? and k.code = r.contract
          where r.import_id = ? and r.ok and r.contract is not null
          union all
          select r.line, r.number, r.due_date, r.amount_cents, r.description, r.roles, c.id, o.contract_id
          from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
          join import_omission o on o.customer_id = c.id
          where r.import_id = ? and r.ok and r.contract is null
        SQL
        Sql.connection.execute("create index on import_bills (customer_id, number)")
        # R57: título pago neste sistema continua pago e não é atualizado pela carga.
        Sql.run(<<~SQL, t)
          delete from import_bills n using bills b where b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number and b.status = 'paid'
        SQL
        Sql.connection.execute("analyze import_bills")
        # Papéis do cliente em cada contrato (R9b): a união do que as linhas declaram (coluna vazia vale os dois), somada ao que o
        # cliente já tinha; uma carga nunca remove papel.
        Sql.run(<<~SQL)
          insert into contract_customers (contract_id, customer_id, roles)
          select contract_id, customer_id,
                 (case when holder then '["holder"]'::jsonb else '[]'::jsonb end) || (case when financial then '["financial_responsible"]'::jsonb else '[]'::jsonb end)
          from (select contract_id, customer_id,
                       bool_or(roles is null or position('holder' in roles) > 0) as holder,
                       bool_or(roles is null or position('financial_responsible' in roles) > 0) as financial
                from import_bills group by contract_id, customer_id) declared
          on conflict (contract_id, customer_id) do update set roles = (
            select coalesce(jsonb_agg(role order by role), '[]'::jsonb)
            from (select distinct jsonb_array_elements_text(contract_customers.roles || excluded.roles) as role) merged)
        SQL

        import.update!(progress_percent: 40, progress_label: "Gravando os títulos")
        # R13: valor, vencimento, contrato e descrição de título existente são atualizados, com registro.
        %w[amount_cents due_date description].each do |field|
          Sql.run(<<~SQL, t, u, i, t)
            insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
            select ?, ?, ?, 'bill', b.id, 'updated', '#{field}', b.#{field}::text, n.#{field}::text, now()
            from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
            where b.#{field} is distinct from n.#{field}
          SQL
        end
        Sql.run(<<~SQL, t, u, i, t)
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
          select ?, ?, ?, 'bill', b.id, 'updated', 'contract', ko.code, kn.code, now()
          from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
          join contracts ko on ko.id = b.contract_id join contracts kn on kn.id = n.contract_id
          where b.contract_id <> n.contract_id
        SQL
        # R16: título retirado que volta fica ativo, com o registro "retirado em X, reincluído em Y".
        Sql.run(<<~SQL, t, u, i, t)
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
          select ?, ?, ?, 'bill', b.id, 'reincluded', 'status', 'withdrawn', 'active', now()
          from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number where b.status = 'withdrawn'
        SQL
        Sql.run(<<~SQL, t, i)
          insert into bills (tenant_id, contract_id, customer_id, number, due_date, amount_cents, description, status, last_import_id, created_at, updated_at)
          select ?, contract_id, customer_id, number, due_date, amount_cents, description, 'active', ?, now(), now() from import_bills
          on conflict (tenant_id, customer_id, number) do update set
            contract_id = excluded.contract_id, due_date = excluded.due_date, amount_cents = excluded.amount_cents,
            description = excluded.description, status = 'active', withdrawn_at = null, withdrawn_import_id = null,
            last_import_id = excluded.last_import_id, updated_at = now()
        SQL

        import.update!(progress_percent: 75, progress_label: "Retirando títulos ausentes")
        # R11 e R14: no batimento, o título ativo que não está no arquivo passa a retirado, sem motivo atribuído.
        return unless import.full_sync?

        Sql.run(<<~SQL, t, i)
          create temporary table import_withdrawn on commit drop as
          select b.id from bills b join customers c on c.id = b.customer_id
          where b.tenant_id = ? and b.status = 'active' and not exists (
            select 1 from import_rows r where r.import_id = ? and r.document = c.document and (r.number = b.number or r.keep_document))
        SQL
        Sql.run(<<~SQL, t, u, i)
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
          select ?, ?, ?, 'bill', id, 'withdrawn', 'status', 'active', 'withdrawn', now() from import_withdrawn
        SQL
        Sql.run("update bills set status = 'withdrawn', withdrawn_at = now(), withdrawn_import_id = ?, updated_at = now() where id in (select id from import_withdrawn)", i)
      end

      # Liga cada contrato de omissão novo (sem cliente) ao cliente que precisava dele, na mesma ordem.
      def link_omission_contracts(tenant_id, import_id)
        Sql.run(<<~SQL, NO_ROLES, tenant_id, tenant_id, import_id, tenant_id)
          insert into contract_customers (contract_id, customer_id, roles)
          select k.id, n.customer_id, ?::jsonb
          from (select k.id, row_number() over (order by k.id) as rn from contracts k
                where k.tenant_id = ? and k.created_by_omission and not exists (select 1 from contract_customers cc where cc.contract_id = k.id)) k
          join (select c.id as customer_id, row_number() over (order by c.id) as rn
                from (select distinct c.id from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
                      where r.import_id = ? and r.ok and r.contract is null
                        and not exists (select 1 from contract_customers cc join contracts k on k.id = cc.contract_id
                                        where cc.customer_id = c.id and k.created_by_omission and k.tenant_id = ?)) c) n on n.rn = k.rn
        SQL
      end
  end
end
