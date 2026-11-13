# Sistemas e identidade (especificação 17, plano técnico da camada 21, etapa 1): cada credor tem
# sistemas (R396 a R399), todo contrato, título e pagamento tem um sistema pai e, em sistema de id próprio, um id remoto (R403, R417), e o cliente
# ganha identidades remotas (R407). A publicação migra a base existente: o que já existe passa ao sistema "Planilha", e o que o CRM criou
# (títulos de acordo, de quebra e de estorno, uso de crédito, instrumento pago) passa ao sistema "CRM".
class SourceSystemsAndIdentity < ActiveRecord::Migration[8.1]
  def up
    create_source_systems
    add_columns
    backfill
    tighten
    replace_indexes
    grant_permission
    # `customer_identities` entra no alcance da operação (decisão 0024): a política vem de `Operations::Rls::READS`.
    Operations::Rls.install!(connection)
  end

  # Os únicos antigos não voltam: o mesmo número pode existir em dois sistemas do credor (R404).
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    def create_source_systems
      create_table :source_systems do |t|
        t.references :tenant, null: false, foreign_key: true, index: false
        t.string :name, limit: 100, null: false
        t.string :role, limit: 10, null: false, default: "remote"
        t.string :key_kind, limit: 10, null: false, default: "natural"
        t.string :status, limit: 10, null: false, default: "active"
        t.timestamps
      end
      # Nome único no credor (R397), sem diferença de maiúsculas; a lista da tela e a escolha no envio leem por credor e usam este índice pelo prefixo.
      add_index :source_systems, "tenant_id, lower(name)", unique: true, name: "index_source_systems_on_tenant_id_and_name"
      # Um CRM e um padrão por credor (R396).
      add_index :source_systems, %i[tenant_id role], unique: true, where: "role <> 'remote'", name: "index_source_systems_one_crm_and_default"
      add_check_constraint :source_systems, "role IN ('crm', 'default', 'remote')", name: "source_systems_role"
      add_check_constraint :source_systems, "key_kind IN ('own_id', 'natural')", name: "source_systems_key_kind"
      add_check_constraint :source_systems, "status IN ('active', 'paused')", name: "source_systems_status"
      # O CRM não é pausado (R396).
      add_check_constraint :source_systems, "role <> 'crm' OR status = 'active'", name: "source_systems_crm_active"

      # Identidade remota do cliente (R407): o id do cliente em cada sistema de id próprio.
      create_table :customer_identities do |t|
        t.references :tenant, null: false, foreign_key: true, index: false
        t.references :source_system, null: false, foreign_key: { on_delete: :restrict }, index: false
        t.references :customer, null: false, foreign_key: { on_delete: :cascade }
        t.string :external_id, limit: 100, null: false
        t.timestamps
      end
      # Identidade por sistema e busca exata em todos os sistemas do credor (R407, R424), pelo prefixo.
      add_index :customer_identities, %i[tenant_id external_id source_system_id], unique: true, name: "index_customer_identities_on_tenant_external_and_system"
    end

    def add_columns
      add_reference :contracts, :source_system, foreign_key: { on_delete: :restrict }, index: false
      add_column :contracts, :external_id, :string, limit: 100
      add_reference :bills, :source_system, foreign_key: { on_delete: :restrict }, index: false
      add_column :bills, :external_id, :string, limit: 100
      add_reference :payments, :source_system, foreign_key: { on_delete: :restrict }, index: false
      add_column :payments, :external_bill_id, :string, limit: 100

      # Quem informou o cliente e o contato, na ordem em que informaram (R411 a R413): o primeiro elemento é quem criou.
      add_column :customers, :source_system_ids, :bigint, array: true, null: false, default: []
      add_column :customer_contacts, :source_system_ids, :bigint, array: true, null: false, default: []

      # A ligação guarda a identidade usada (R409); apagar a identidade (anonimização) não apaga a ligação.
      add_reference :contract_customers, :customer_identity, foreign_key: { on_delete: :nullify }, index: false

      add_reference :imports, :source_system, foreign_key: { on_delete: :restrict }, index: false
      add_reference :changes, :source_system, foreign_key: { on_delete: :nullify }, index: false

      # Preparação da carteira: os ids remotos da linha (R401) e a mudança a confirmar (R409a).
      change_table :import_rows, bulk: true do |t|
        t.string :external_bill_id, limit: 100
        t.string :external_contract_id, limit: 100
        t.string :external_customer_id, limit: 100
        t.string :hold_kind, limit: 20
        t.string :hold_blocked_reason, limit: 300
        t.boolean :hold_confirmed, null: false, default: false
      end
      # Retirada em sistema de id próprio: a linha da preparação pelo id do título. Escrita uma vez por carga e apagada ao fim.
      add_index :import_rows, %i[import_id external_bill_id]

      # Preparação dos pagamentos: o sistema da linha (R416), o id remoto do título (R417), o título do instrumento pago (R417b) e o pendente
      # que muda de sistema (R418).
      change_table :payment_rows, bulk: true do |t|
        t.bigint :source_system_id
        t.string :external_bill_id, limit: 100
        t.bigint :target_bill_id
        t.bigint :repoint_payment_id
      end

      # Política "Cadastro entre sistemas" (R410).
      add_column :tenant_settings, :customer_record_policy, :string, limit: 20, null: false, default: "last_sender"
      add_reference :tenant_settings, :customer_record_system, foreign_key: { to_table: :source_systems, on_delete: :restrict }, index: false
      add_check_constraint :tenant_settings, "customer_record_policy IN ('last_sender', 'defined_system', 'first_creator')", name: "tenant_settings_customer_record_policy"
      add_check_constraint :tenant_settings, "(customer_record_policy = 'defined_system') = (customer_record_system_id IS NOT NULL)", name: "tenant_settings_customer_record_system"
    end

    # `Tenant.provision!` não alcança os credores que já existem: os dois sistemas nascem aqui, em SQL.
    def backfill
      execute(<<~SQL)
        INSERT INTO source_systems (tenant_id, name, role, key_kind, status, created_at, updated_at)
        SELECT tenants.id, names.name, names.role, 'natural', 'active', now(), now()
        FROM tenants CROSS JOIN (VALUES ('CRM', 'crm'), ('Planilha', 'default')) AS names (name, role)
      SQL

      execute("UPDATE contracts SET source_system_id = #{system_of('contracts', 'default')}")
      execute(<<~SQL)
        UPDATE bills SET source_system_id = CASE WHEN bills.kind = 'common' THEN #{system_of('bills', 'default')} ELSE #{system_of('bills', 'crm')} END
      SQL
      # Uso de crédito do contrato e instrumento pago são pagamentos do CRM (R416, R417b); os demais vieram de planilha ou de webhook do credor.
      execute(<<~SQL)
        UPDATE payments SET source_system_id = CASE
          WHEN payments.channel_id IN (SELECT id FROM payment_channels WHERE code = 'CRM-CREDITO')
            OR payments.id IN (SELECT payment_id FROM payment_instruments WHERE payment_id IS NOT NULL)
          THEN #{system_of('payments', 'crm')} ELSE #{system_of('payments', 'default')} END
      SQL
      # Sem isto, a R411 trataria cliente e contato existentes como nunca informados pelo Planilha.
      execute("UPDATE customers SET source_system_ids = ARRAY[#{system_of('customers', 'default')}]")
      execute("UPDATE customer_contacts SET source_system_ids = ARRAY[#{system_of('customer_contacts', 'default')}]")
      execute("UPDATE imports SET source_system_id = #{system_of('imports', 'default')} WHERE imports.kind = 'portfolio'")
    end

    def system_of(table, role)
      "(SELECT source_systems.id FROM source_systems WHERE source_systems.tenant_id = #{table}.tenant_id AND source_systems.role = '#{role}')"
    end

    def tighten
      change_column_null :contracts, :source_system_id, false
      change_column_null :bills, :source_system_id, false
      change_column_null :payments, :source_system_id, false
    end

    # Decisão 0010: cada índice e a consulta que o usa estão no plano técnico, seção "Índices e a consulta que usa cada um".
    def replace_indexes
      # Chave natural (sem id remoto): o número é único por cliente dentro do sistema (R404).
      add_index :bills, %i[tenant_id source_system_id customer_id number], unique: true, where: "external_id IS NULL", name: "index_bills_on_system_customer_and_number"
      add_index :bills, %i[tenant_id source_system_id external_id], unique: true, where: "external_id IS NOT NULL", name: "index_bills_on_system_and_external_id"
      remove_index :bills, name: "index_bills_on_tenant_id_and_customer_id_and_number"

      add_index :contracts, %i[tenant_id source_system_id code], unique: true, where: "external_id IS NULL AND code IS NOT NULL", name: "index_contracts_on_system_and_code"
      add_index :contracts, %i[tenant_id source_system_id external_id], unique: true, where: "external_id IS NOT NULL", name: "index_contracts_on_system_and_external_id"
      remove_index :contracts, name: "index_contracts_on_tenant_id_and_code"
      # O código digitado procura em todos os sistemas do credor (R421): mesma coluna do único antigo, sem a unicidade.
      add_index :contracts, %i[tenant_id code], where: "code IS NOT NULL", name: "index_contracts_on_tenant_id_and_code"
    end

    # O perfil Gestor padrão recebe "configurar integração" (23), como os credores novos; o Operador não.
    def grant_permission
      execute(<<~SQL)
        UPDATE profiles SET permissions = permissions || '["configure_integration"]'::jsonb
        WHERE name = 'Gestor' AND NOT permissions @> '["configure_integration"]'::jsonb
      SQL
    end
end
