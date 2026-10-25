module Portfolio
  # Confirmação da importação (R10): grava só as linhas válidas, numa única transação, em SQL em lote (decisão 0004). Clientes,
  # contratos, títulos, retiradas e o histórico de alterações saem da tabela de preparação; nada é gravado se qualquer passo falhar.
  class ImportConfirmer
    # Papéis de um cliente que entra num contrato: nascem vazios e são preenchidos, em seguida, pelos papéis declarados nas linhas
    # da planilha (R9b); coluna `papel` vazia vale os dois papéis.
    NO_ROLES = "[]".freeze
    TEMPORARY_TABLES = %w[import_customers import_new_customers import_new_customer_ids import_contact_rows import_omission import_bills import_withdrawn import_discrepancies import_before].freeze

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
      %w[customers customer_contacts contracts contract_customers bills].each { |table| Sql.connection.execute("analyze #{table}") }
      Sql.run("delete from import_rows where import_id = ?", import.id)
      Sql.run("delete from import_contacts where import_id = ?", import.id)
      FileUtils.rm_f(import.file_path) if import.stored_path
      import.update!(status: :confirmed, progress_percent: 100, progress_label: nil, finished_at: Time.current)
    end

    private
      def write(import)
        t = import.tenant_id
        i = import.id
        u = import.user_id
        # Memória de trabalho maior só nesta transação: as junções por hash dos contatos (1,2 milhão de linhas na V4 de cadastros) gastavam o
        # tempo em arquivos temporários com os 4 MB padrão. O banco tem limite de 1 GB e há uma confirmação por credor.
        Sql.execute("set local work_mem = '96MB'")
        # As tabelas temporárias somem no fim da transação; o descarte explícito cobre a transação aninhada (como nos testes).
        TEMPORARY_TABLES.each { |name| Sql.connection.execute("drop table if exists #{name}") }

        # Uma linha por cliente: o nome da última linha válida do documento. Os contatos vêm da tabela própria (06, R109).
        Sql.run(<<~SQL, i)
          create temporary table import_customers on commit drop as
          select distinct on (document) document, name from import_rows where import_id = ? and ok order by document, line desc
        SQL
        Sql.connection.execute("analyze import_customers")
        # Clientes que ainda não existem: a criação do cliente já é o registro, então os contatos deles não geram histórico um a um.
        Sql.run(<<~SQL, t)
          create temporary table import_new_customers on commit drop as
          select ic.document from import_customers ic where not exists (select 1 from customers c where c.tenant_id = ? and c.document = ic.document)
        SQL
        # R8 e R117: a mudança de nome fica registrada; com "a tela prevalece", o nome marcado "mantido pelo credor" não muda.
        screen_prevails = import.tenant.setting.correction_policy_screen?
        Sql.run(<<~SQL, t, u, i, t, screen_prevails)
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, origin, occurred_at)
          select ?, ?, ?, 'customer', c.id, 'updated', 'name', c.name, new.name, 'load', now()
          from import_customers new join customers c on c.tenant_id = ? and c.document = new.document
          where c.name is distinct from new.name and not (c.name_kept and ?::boolean)
        SQL
        Sql.run(<<~SQL, t, screen_prevails, screen_prevails, screen_prevails)
          insert into customers (tenant_id, document, name, created_at, updated_at)
          select ?, document, name, now(), now() from import_customers
          on conflict (tenant_id, document) do update set
            name = case when customers.name_kept and ?::boolean then customers.name else excluded.name end,
            name_kept = customers.name_kept and ?::boolean, updated_at = now()
          where customers.name is distinct from excluded.name or (customers.name_kept and not ?::boolean)
        SQL
        write_contacts(import, !screen_prevails)
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
          select r.line, r.number, r.due_date, r.amount_cents, r.description, r.roles, r.product, r.penalty_cents, r.interest_cents, r.correction_cents,
                 r.other_cents, c.id as customer_id, k.id as contract_id
          from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
          join contracts k on k.tenant_id = ? and k.code = r.contract
          where r.import_id = ? and r.ok and r.contract is not null
          union all
          select r.line, r.number, r.due_date, r.amount_cents, r.description, r.roles, r.product, r.penalty_cents, r.interest_cents, r.correction_cents,
                 r.other_cents, c.id, o.contract_id
          from import_rows r join customers c on c.tenant_id = ? and c.document = r.document
          join import_omission o on o.customer_id = c.id
          where r.import_id = ? and r.ok and r.contract is null
        SQL
        Sql.connection.execute("create index on import_bills (customer_id, number)")
        policy = import.tenant.setting.discrepancy_policy
        write_discrepancies(import, policy)
        # R57: título pago neste sistema continua pago e não é atualizado pela carga.
        Sql.run(<<~SQL, t)
          delete from import_bills n using bills b where b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number and b.status = 'paid'
        SQL
        Sql.connection.execute("analyze import_bills")
        # Valor anterior dos títulos que a carga atualiza, para criar a versão só quando o valor vigente mudou (R88).
        Sql.run(<<~SQL, t)
          create temporary table import_before on commit drop as
          select b.id as bill_id, b.amount_cents from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
        SQL
        Sql.connection.execute("create unique index on import_before (bill_id)")
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
          insert into bills (tenant_id, contract_id, customer_id, number, due_date, amount_cents, description, product, status, last_import_id, created_at, updated_at)
          select ?, contract_id, customer_id, number, due_date, amount_cents, description, product, 'active', ?, now(), now() from import_bills
          on conflict (tenant_id, customer_id, number) do update set
            contract_id = excluded.contract_id, due_date = excluded.due_date, amount_cents = excluded.amount_cents,
            description = excluded.description, product = coalesce(excluded.product, bills.product), status = 'active', withdrawn_at = null,
            withdrawn_import_id = null, last_import_id = excluded.last_import_id, updated_at = now()
        SQL
        settle_and_version(import)

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

      # Contatos da carga (06, R109, R117, R126), em SQL de conjunto: um contato igual a um que o cliente já tem só atualiza a data em que veio
      # (com "a carga vence", também o devolve a válido, com registro); o novo é criado, inválido se for igual ao do credor. A carga nunca apaga
      # nem desativa um contato. O histórico é gravado no mesmo comando (`returning old/new`). Consultas: `customer_contacts (customer_id, kind, key)`.
      def write_contacts(import, load_wins)
        t = import.tenant_id
        i = import.id
        u = import.user_id
        # Um contato por linha da preparação (as recusadas já saíram na conferência). O mesmo contato em duas linhas do cliente aparece duas
        # vezes: a atualização usa uma delas e o `ON CONFLICT DO NOTHING` da inserção descarta a outra, sem a ordenação que um DISTINCT exigiria.
        Sql.run(<<~SQL, t, i)
          create temporary table import_contact_rows on commit drop as
          select c.id as customer_id, c.document, ic.kind, ic.key, ic.value, ic.street, ic.number, ic.complement, ic.district,
                 ic.city, ic.state, ic.zip, ic.tenant_contact
          from import_contacts ic join customers c on c.tenant_id = ? and c.document = ic.document
          where ic.import_id = ?
        SQL
        Sql.connection.execute("create index on import_contact_rows (customer_id, kind, key)")
        Sql.connection.execute("analyze import_contact_rows")
        Sql.run("create temporary table import_new_customer_ids on commit drop as select c.id from customers c join import_new_customers x on x.document = c.document where c.tenant_id = ?", t)
        Sql.connection.execute("create index on import_new_customer_ids (id)")

        reactivate = "(#{load_wins ? 'true' : 'false'} and k.status <> 'valid' and not n.tenant_contact)"
        Sql.run(<<~SQL, t, u, i)
          with touched as (
            update customer_contacts k set
              status = case when #{reactivate} then 'valid' else k.status end,
              reason = case when #{reactivate} then 'a carga vence' else k.reason end,
              do_not_disturb_on = case when #{reactivate} then null else k.do_not_disturb_on end,
              kept_by_tenant = case when #{reactivate} then false else k.kept_by_tenant end,
              updated_at = case when #{reactivate} then now() else k.updated_at end,
              updated_by_id = case when #{reactivate} then null else k.updated_by_id end,
              seen_in_import_at = now()
            from import_contact_rows n where k.customer_id = n.customer_id and k.kind = n.kind and k.key = n.key
            returning k.id, old.status as before_status, new.status as after_status
          )
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, note, origin, occurred_at)
          select ?, ?, ?, 'customer_contact', id, 'status_changed', 'status', before_status, after_status, 'a carga vence', 'load', now()
          from touched where before_status <> after_status
        SQL
        Sql.run(<<~SQL, t, t, u, i)
          with inserted as (
            insert into customer_contacts (tenant_id, customer_id, kind, key, value, street, number, complement, district, city, state, zip, origin, status, reason,
                                           kept_by_tenant, seen_in_import_at, created_at, updated_at)
            select ?, customer_id, kind, key, value, street, number, complement, district, city, state, zip, 'load',
                   case when tenant_contact then 'invalid' else 'valid' end, case when tenant_contact then 'é contato do credor' end, false, now(), now(), now()
            from import_contact_rows
            on conflict (customer_id, kind, key) do nothing
            returning id, customer_id, status, reason
          )
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, note, origin, occurred_at)
          select ?, ?, ?, 'customer_contact', id, 'created', 'status', null, status, reason, 'load', now()
          from inserted where not exists (select 1 from import_new_customer_ids x where x.id = inserted.customer_id)
        SQL
      end

      # R93 a R98: os títulos com pagamento cujo valor muda ganham uma divergência aberta, com o efeito da política da hora da confirmação. Com
      # "manter e registrar", o valor informado fica só na divergência e o título segue com o vigente (a linha da carga é ajustada aqui).
      # Roda antes do R57 porque o título pago também gera divergência, só para registro (R96).
      def write_discrepancies(import, policy)
        t = import.tenant_id
        reported = "n.amount_cents"
        Sql.run(<<~SQL, t)
          create temporary table import_discrepancies on commit drop as
          select b.id as bill_id, b.customer_id, b.number, b.amount_cents as previous_cents, n.amount_cents as reported_cents, b.paid_cents as allocated_cents,
                 #{DiscrepancyRules.balance_before_sql} as balance_before_cents, #{DiscrepancyRules.balance_after_sql(policy, reported)} as balance_after_cents,
                 #{DiscrepancyRules.excess_sql(policy, reported)} as excess_cents, #{DiscrepancyRules.effect_sql(policy, reported)} as effect
          from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
          where b.amount_cents <> n.amount_cents and #{DiscrepancyRules::WITH_ALLOCATION}
        SQL
        Sql.run(<<~SQL, t, import.id, policy.to_s)
          insert into value_discrepancies (tenant_id, bill_id, import_id, previous_cents, reported_cents, allocated_cents, balance_before_cents,
                                           balance_after_cents, excess_cents, effect, policy, status, created_at, updated_at)
          select ?, bill_id, ?, previous_cents, reported_cents, allocated_cents, balance_before_cents, balance_after_cents, excess_cents, effect, ?, 'open',
                 now(), now()
          from import_discrepancies
        SQL
        return unless policy.to_s == "keep"

        Sql.execute("update import_bills n set amount_cents = d.previous_cents from import_discrepancies d where d.customer_id = n.customer_id and d.number = n.number and d.effect = 'kept'")
      end

      # Depois de gravar os títulos: os que a política "seguir" quitou passam a pago (R94, R97), a versão do valor nasce para o título novo e
      # para o que mudou de valor (R88) e os acréscimos informados pelo credor são guardados (R102).
      def settle_and_version(import)
        t = import.tenant_id
        i = import.id
        u = import.confirmed_by_id || import.user_id
        Sql.run(<<~SQL, t, u, i)
          insert into changes (tenant_id, user_id, import_id, subject_type, subject_id, event, field, before, after, occurred_at)
          select ?, ?, ?, 'bill', bill_id, 'settled_by_value', 'status', 'active', 'paid', now() from import_discrepancies where effect in ('becomes_paid', 'returns_paid')
        SQL
        Sql.execute(<<~SQL)
          update bills set status = 'paid', updated_at = now(),
                 paid_on = coalesce((select max(p.paid_on) from payments p where p.bill_id = bills.id and p.status = 'applied'), current_date)
          where id in (select bill_id from import_discrepancies where effect in ('becomes_paid', 'returns_paid'))
        SQL
        Sql.run(<<~SQL, i, u, t)
          insert into bill_value_versions (tenant_id, bill_id, amount_cents, import_id, user_id, created_at)
          select b.tenant_id, b.id, b.amount_cents, ?, ?, now()
          from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
          left join import_before ob on ob.bill_id = b.id
          where ob.bill_id is null or ob.amount_cents <> b.amount_cents
        SQL
        Sql.run(<<~SQL, i, t)
          insert into reported_surcharges (tenant_id, bill_id, import_id, penalty_cents, interest_cents, correction_cents, other_cents, created_at, updated_at)
          select b.tenant_id, b.id, ?, coalesce(n.penalty_cents, 0), coalesce(n.interest_cents, 0), coalesce(n.correction_cents, 0), coalesce(n.other_cents, 0), now(), now()
          from import_bills n join bills b on b.tenant_id = ? and b.customer_id = n.customer_id and b.number = n.number
          where n.penalty_cents is not null or n.interest_cents is not null or n.correction_cents is not null or n.other_cents is not null
          on conflict (bill_id) do update set import_id = excluded.import_id, penalty_cents = excluded.penalty_cents, interest_cents = excluded.interest_cents,
            correction_cents = excluded.correction_cents, other_cents = excluded.other_cents, updated_at = now()
        SQL
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
