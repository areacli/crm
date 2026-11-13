module Operations
  # Row-Level Security do alcance das operações (14, R313, R314; decisão 0024). Idempotente: a migração o chama, e também a preparação de cada
  # banco de teste e a carga do esquema, porque o `schema.rb` não guarda papéis nem políticas (e o `pg_dump` da imagem, versão 17, não exporta o
  # servidor 19, então o `structure.sql` fica para quando o cliente do PostgreSQL da imagem acompanhar).
  #
  # Dois papéis sem login, escolhidos por `SET ROLE` no começo de cada requisição (`Operations::Context`): `crm_team` (equipe do credor e o
  # sistema: vê tudo, o recorte por credor continua nas permissões) e `crm_operation` (usuário de operação: vê só o que está pra a operação dele,
  # pelas tabelas de alcance que `Operations::ReachBuilder` mantém). As políticas são de leitura; as escritas passam (a política de leitura vale
  # também no WHERE de UPDATE e DELETE, e os serviços que mexem além do que está pra o usuário rodam em `Operations::Context.system`).
  module Rls
    module_function

    ROLES = %w[crm_team crm_operation].freeze
    # Papel de entrada da aplicação em produção: sem superusuário, sem BYPASSRLS, sem ser dono. Lê as tabelas sem política (usuários, sessões,
    # configuração) e nada das tabelas de carteira até declarar `crm_team` ou `crm_operation` (falha fechada): é membro dos dois sem herdar
    # os privilégios deles, só para poder trocar de papel.
    APP_ROLE = "crm_app".freeze

    # Cria ou atualiza o papel de entrada com a senha dada e as permissões (roda como o dono, na publicação).
    def create_login!(role, password, connection = ActiveRecord::Base.connection)
      quoted = connection.quote(password)
      exists = connection.select_value("SELECT 1 FROM pg_roles WHERE rolname = #{connection.quote(role)}")
      connection.execute("#{exists ? 'ALTER' : 'CREATE'} ROLE #{connection.quote_column_name(role)} LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE PASSWORD #{quoted}")
      install!(connection)
      grant_login!(role, connection)
    end

    def grant_login!(role, connection = ActiveRecord::Base.connection)
      name = connection.quote_column_name(role)
      connection.execute(<<~SQL)
        GRANT CONNECT, TEMPORARY ON DATABASE #{connection.quote_column_name(connection.current_database)} TO #{name};
        GRANT USAGE ON SCHEMA public TO #{name};
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, MAINTAIN ON ALL TABLES IN SCHEMA public TO #{name};
        GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO #{name};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, MAINTAIN ON TABLES TO #{name};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO #{name};
        GRANT #{ROLES.join(', ')} TO #{name} WITH INHERIT FALSE, SET TRUE;
      SQL
    end

    # Tabela => condição de leitura para `crm_operation`. `crm_operation()` lê a operação declarada na requisição.
    # As condições usam `coluna IN (subconsulta sem correlação)`, que o PostgreSQL resolve com uma tabela hash montada uma vez por consulta; um
    # `EXISTS` correlacionado vira uma busca no índice por linha, e a política roda antes de qualquer filtro da consulta (barreira de segurança):
    # numa soma sobre 600 mil títulos, eram 600 mil buscas (medição de 31/10/2026, no plano técnico da camada 18).
    OP_CONTRACTS = "SELECT contract_id FROM operation_contracts WHERE operation_id = crm_operation()".freeze
    OP_CUSTOMERS = "SELECT customer_id FROM operation_customers WHERE operation_id = crm_operation()".freeze

    READS = {
      "customers" => "customers.id IN (#{OP_CUSTOMERS})",
      "contracts" => "contracts.id IN (#{OP_CONTRACTS})",
      "contract_customers" => "contract_customers.contract_id IN (#{OP_CONTRACTS})",
      # Exposição "vencidas": o contrato passa pelo hash e a data da fatura é comparada com o corte do credor, declarado com o contexto da
      # requisição (`crm.cutoffs`); sem o corte do credor, a fatura não aparece.
      "bills" => <<~SQL.squish,
        bills.contract_id IN (#{OP_CONTRACTS} AND mode = 'all')
        OR bills.id IN (SELECT bill_id FROM operation_bills WHERE operation_id = crm_operation())
        OR (bills.contract_id IN (#{OP_CONTRACTS} AND mode = 'overdue') AND bills.due_date < crm_cutoff(bills.tenant_id))
      SQL
      "customer_contacts" => "customer_contacts.customer_id IN (#{OP_CUSTOMERS})",
      # Identidade remota do cliente (17, R407): acompanha o cliente.
      "customer_identities" => "customer_identities.customer_id IN (#{OP_CUSTOMERS})",
      "contact_attempts" => <<~SQL.squish,
        contact_attempts.customer_id IN (#{OP_CUSTOMERS})
        AND (contact_attempts.contract_id IS NULL OR contact_attempts.contract_id IN (#{OP_CONTRACTS}))
        AND (contact_attempts.operation_id = crm_operation()
             OR contact_attempts.tenant_id IN (SELECT tenant_id FROM tenant_settings WHERE operation_other_contact_attempts = 'summary'))
      SQL
      "payment_promises" => <<~SQL.squish,
        payment_promises.operation_id = crm_operation()
        OR (payment_promises.contract_id IN (#{OP_CONTRACTS})
            AND payment_promises.tenant_id IN (SELECT tenant_id FROM tenant_settings WHERE operation_sees_other_deals))
      SQL
      "agreements" => <<~SQL.squish,
        agreements.operation_id = crm_operation()
        OR (agreements.customer_id IN (#{OP_CUSTOMERS})
            AND agreements.tenant_id IN (SELECT tenant_id FROM tenant_settings WHERE operation_sees_other_deals))
      SQL
      "payment_promise_bills" => "EXISTS (SELECT 1 FROM payment_promises p WHERE p.id = payment_promise_bills.promise_id)",
      "agreement_bills" => "EXISTS (SELECT 1 FROM agreements a WHERE a.id = agreement_bills.agreement_id)",
      "agreement_events" => "EXISTS (SELECT 1 FROM agreements a WHERE a.id = agreement_events.agreement_id)",
      "payments" => "payments.bill_id IS NOT NULL AND EXISTS (SELECT 1 FROM bills b WHERE b.id = payments.bill_id)",
      # O histórico de alterações guarda antes e depois de qualquer registro do credor: a operação só lê o que ela mesma fez (o Rails grava com
      # RETURNING, que exige ler a linha nova).
      "changes" => "changes.user_id = crm_user()",
      # As distribuições e a trilha: a operação só lê as suas (e a linha que ela mesma grava, pelo RETURNING).
      "distributions" => "distributions.operation_id = crm_operation()",
      "operation_trail_events" => "operation_trail_events.user_id = crm_user()",
      # Lotes de distribuição (14, R316): o resumo traz códigos de contrato, documentos da planilha e saldo. A operação só lê os que ela mesma pediu.
      "distribution_batches" => "distribution_batches.user_id = crm_user()",
      # Importações e arquivo de acordos: o resumo da conferência e o arquivo trazem título, documento e nome do credor inteiro. A operação só lê os que ela mesma pediu.
      "imports" => "imports.user_id = crm_user()",
      "agreement_exports" => "agreement_exports.user_id = crm_user()",
      # Filas (15): onde está e quem recebeu cada sujeito; a operação só vê, e o "Próximo" só entrega, o que está pra ela (R353).
      "queue_placements" => <<~SQL.squish,
        (queue_placements.subject = 'contracts' AND queue_placements.subject_id IN (#{OP_CONTRACTS}))
        OR (queue_placements.subject = 'customers' AND queue_placements.subject_id IN (#{OP_CUSTOMERS}))
      SQL
      "queue_deliveries" => <<~SQL.squish,
        (queue_deliveries.subject = 'contracts' AND queue_deliveries.subject_id IN (#{OP_CONTRACTS}))
        OR (queue_deliveries.subject = 'customers' AND queue_deliveries.subject_id IN (#{OP_CUSTOMERS}))
      SQL
      # Lotes de emissão (16, R384, R387): a operação só lê os que ela mesma pediu (a conferência roda no contexto de quem pediu).
      "instrument_batches" => "instrument_batches.created_by_id = crm_user()"
    }.merge(
      # Tabelas de valores ligadas a uma fatura, um contrato, um acordo ou um cliente: visíveis quando o registro pai é (a política do pai vale
      # dentro da subconsulta). Não têm nome nem documento, mas uma tela que as liste mostraria valores do que não está pra a operação.
      {
        "abatements" => "bills", "bill_valuations" => "bills", "bill_value_versions" => "bills", "payment_allocations" => "bills",
        "reported_surcharges" => "bills", "value_discrepancies" => "bills", "credits" => "contracts", "contract_tiers" => "contracts",
        "reversal_waits" => "contracts", "agreement_settlements" => "agreements", "payment_checkouts" => "customers", "payment_instruments" => "customers"
      }.to_h do |table, parent|
        column = { "bills" => "bill_id", "contracts" => "contract_id", "agreements" => "agreement_id", "customers" => "customer_id" }.fetch(parent)
        [ table, "EXISTS (SELECT 1 FROM #{parent} p WHERE p.id = #{table}.#{column})" ]
      end
    ).freeze

    def install!(connection = ActiveRecord::Base.connection)
      connection.execute(<<~SQL)
        DO $$ BEGIN
          #{ROLES.map { |role| "IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{role}') THEN CREATE ROLE #{role} NOLOGIN; END IF;" }.join("\n          ")}
        END $$;
        GRANT USAGE ON SCHEMA public TO #{ROLES.join(', ')};
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, MAINTAIN ON ALL TABLES IN SCHEMA public TO #{ROLES.join(', ')};
        GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO #{ROLES.join(', ')};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, MAINTAIN ON TABLES TO #{ROLES.join(', ')};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO #{ROLES.join(', ')};
        CREATE OR REPLACE FUNCTION crm_operation() RETURNS bigint LANGUAGE sql STABLE AS $f$ SELECT nullif(current_setting('crm.operation', true), '')::bigint $f$;
        CREATE OR REPLACE FUNCTION crm_user() RETURNS bigint LANGUAGE sql STABLE AS $f$ SELECT nullif(current_setting('crm.user', true), '')::bigint $f$;
        CREATE OR REPLACE FUNCTION crm_cutoff(tenant bigint) RETURNS date LANGUAGE sql STABLE AS
          $f$ SELECT (nullif(current_setting('crm.cutoffs', true), '')::jsonb ->> tenant::text)::date $f$;
      SQL
      grant_login!(APP_ROLE, connection) if connection.select_value("SELECT 1 FROM pg_roles WHERE rolname = '#{APP_ROLE}'")
      READS.each do |table, condition|
        connection.execute(<<~SQL)
          ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
          DROP POLICY IF EXISTS team_all ON #{table};
          DROP POLICY IF EXISTS operation_read ON #{table};
          DROP POLICY IF EXISTS operation_insert ON #{table};
          DROP POLICY IF EXISTS operation_update ON #{table};
          DROP POLICY IF EXISTS operation_delete ON #{table};
          CREATE POLICY team_all ON #{table} TO crm_team USING (true) WITH CHECK (true);
          CREATE POLICY operation_read ON #{table} FOR SELECT TO crm_operation USING (#{condition});
          -- Escritas por comando (uma política FOR ALL valeria também para a leitura e a abriria inteira).
          CREATE POLICY operation_insert ON #{table} FOR INSERT TO crm_operation WITH CHECK (true);
          CREATE POLICY operation_update ON #{table} FOR UPDATE TO crm_operation USING (true) WITH CHECK (true);
          CREATE POLICY operation_delete ON #{table} FOR DELETE TO crm_operation USING (true);
        SQL
      end
    end

    # Tabelas com dado de carteira que têm RLS (o teste de arquitetura confere que nenhuma tabela nova com cliente, contrato ou título fica de fora).
    def tables = READS.keys
  end
end
