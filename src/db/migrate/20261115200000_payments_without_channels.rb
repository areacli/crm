# O método de recebimento (antes canal) sai do produto (16, revisão 2; 03, revisão 12): o pagamento e o estorno passam a ser identificados por
# credor, fornecedor, conta e identificador; o meio continua obrigatório, fora da identidade. O fornecedor e a conta ficam com a chave lida sem
# maiúsculas, acentos, espaços e hífens (`provider`, `account_key`) e com o texto como foi escrito (`provider_name`, `account_code`). O código do
# método era o código da conta: ele passa à conta dos pagamentos e das integrações (`payment_accounts.account_code`, 12, R260). O fornecedor dos
# pagamentos que já existem é o da integração do método ou, sem integração, o código do método; o uso de crédito do contrato passa ao meio interno
# `contract_credit`, com o fornecedor e a conta "CRM". Sem volta: o método some.
class PaymentsWithoutChannels < ActiveRecord::Migration[8.1]
  # Chave do fornecedor no banco, a mesma de `PaymentProvider.key`: minúsculas, sem acentos comuns, sem espaço, hífen, sublinhado nem ponto.
  FOLD = "regexp_replace(translate(lower(%s), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'), '[[:space:]._-]+', '', 'g')".freeze

  def up
    add_column :payments, :provider, :string, limit: 100
    add_column :payments, :provider_name, :string, limit: 100
    add_column :payments, :account_key, :string, limit: 100
    add_column :payments, :account_code, :string, limit: 100
    add_column :payment_accounts, :account_code, :string, limit: 100
    execute "update payment_accounts a set account_code = ch.code from payment_channels ch where ch.id = a.channel_id"
    change_column_null :payment_accounts, :account_code, false

    execute <<~SQL
      update payments p set payment_method = 'contract_credit', provider = 'crm', provider_name = 'CRM', account_key = 'crm', account_code = 'CRM'
      from payment_channels ch where ch.id = p.channel_id and ch.code = 'CRM-CREDITO'
    SQL
    execute <<~SQL
      update payments p set provider = coalesce(a.provider, #{format(FOLD, 'ch.code')}), provider_name = coalesce(a.provider_name, ch.description),
                            account_key = #{format(FOLD, 'ch.code')}, account_code = ch.code
      from payment_channels ch
      left join lateral (
        select pa.provider, case pa.provider when 'efi' then 'Efí' when 'bradesco' then 'Bradesco' when 'pagbank' then 'PagBank'
                                             when 'mercadopago' then 'Mercado Pago' else pa.provider end as provider_name
        from payment_accounts pa where pa.channel_id = ch.id order by pa.active desc, pa.id limit 1) a on true
      where ch.id = p.channel_id and p.provider is null
    SQL
    change_column_null :payments, :provider, false
    change_column_null :payments, :provider_name, false
    change_column_null :payments, :account_key, false
    change_column_null :payments, :account_code, false

    add_column :payment_reversals, :payment_method, :string, limit: 20
    add_column :payment_reversals, :provider, :string, limit: 100
    add_column :payment_reversals, :account_key, :string, limit: 100
    execute <<~SQL
      update payment_reversals r set payment_method = p.payment_method, provider = p.provider, account_key = p.account_key from payments p where p.id = r.payment_id
    SQL
    change_column_null :payment_reversals, :payment_method, false
    change_column_null :payment_reversals, :provider, false
    change_column_null :payment_reversals, :account_key, false

    remove_index :payments, %i[tenant_id channel_id identifier]
    remove_index :payment_reversals, %i[tenant_id channel_id identifier]
    remove_reference :payments, :channel, foreign_key: { to_table: :payment_channels }, index: false
    remove_reference :payment_reversals, :channel, foreign_key: { to_table: :payment_channels }, index: false
    # R48 e R61: a identidade do pagamento e a do estorno; os mesmos índices atendem à conferência ("já registrado") e ao aviso do fornecedor.
    add_index :payments, %i[tenant_id provider account_key identifier], unique: true
    add_index :payment_reversals, %i[tenant_id provider account_key identifier], unique: true

    # A preparação da conferência: a linha traz o fornecedor e a conta no lugar do código do método (as linhas antigas, já confirmadas ou
    # descartadas, ficam com o código do método como fornecedor e como conta).
    remove_index :payment_rows, %i[import_id channel_code identifier]
    rename_column :payment_rows, :channel_code, :provider
    add_column :payment_rows, :provider_name, :string, limit: 100
    add_column :payment_rows, :account_key, :string, limit: 100
    add_column :payment_rows, :account_code, :string, limit: 100
    execute "update payment_rows set account_key = provider, account_code = provider"
    change_column_null :payment_rows, :account_key, false
    add_index :payment_rows, %i[import_id provider account_key identifier]

    remove_reference :payment_accounts, :channel, foreign_key: { to_table: :payment_channels }, index: true
    # O aviso sem fornecedor era por método (plano técnico da camada 6); cada fornecedor tem o seu (12).
    drop_table :webhook_events
    drop_table :payment_channels
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "o método de recebimento saiu do produto (16, revisão 2); volte pela cópia do banco"
  end
end
