# Camada 7 (incremento 4): resultados de acionamento (lista do credor) e acionamentos. Índices: cada um diz a consulta que o usa
# (decisão 0010); o custo na escrita foi medido na V4 (`crm:measure_contacts`).
class CreateContactAttempts < ActiveRecord::Migration[8.1]
  # Lista inicial (R68), copiada aqui para os credores que já existem; o código novo a tem em `Contacts::InitialResults`.
  INITIAL = [
    [ "Pediu para retornar depois", "spoke_with_customer", "required" ], [ "Negociação em andamento", "spoke_with_customer", "allowed" ],
    [ "Disse que já pagou", "spoke_with_customer", "allowed" ], [ "Contesta a dívida", "spoke_with_customer", "allowed" ],
    [ "Recusou pagar", "spoke_with_customer", "allowed" ], [ "Recado com terceiro", "spoke_with_third_party", "allowed" ],
    [ "Terceiro não conhece o cliente", "spoke_with_third_party", "not_allowed" ], [ "Não atendeu", "no_contact", "allowed" ],
    [ "Caixa postal", "no_contact", "allowed" ], [ "Mensagem enviada, sem resposta", "no_contact", "allowed" ],
    [ "Número ou endereço inexistente", "no_contact", "not_allowed" ]
  ].freeze

  def change
    # Resultado do acionamento (R66): nome único no credor sem diferença de maiúsculas e acentos (`name_key`), tipo fixo e regra de retorno.
    create_table :contact_results do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, null: false, limit: 100
      t.string :name_key, null: false, limit: 100
      t.string :kind, null: false, limit: 30
      t.string :return_rule, null: false, limit: 20
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    # Unicidade do nome no credor (R66) e a lista na ordem escolhida pelo gestor.
    add_index :contact_results, %i[tenant_id name_key], unique: true
    add_index :contact_results, %i[tenant_id position]

    # Acionamento (R69): só inserção, nunca editado nem anulado (04, revisão 5). `result_kind` copia o tipo do resultado no registro, que nunca
    # muda (R66); assim o resumo conta por tipo sem juntar tabelas.
    create_table :contact_attempts do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.references :contract, foreign_key: { on_delete: :restrict }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.references :result, null: false, foreign_key: { to_table: :contact_results, on_delete: :restrict }, index: false
      t.string :result_kind, null: false, limit: 30
      t.string :channel, null: false, limit: 20
      t.string :contact_used, limit: 300
      t.text :text
      t.datetime :contacted_at, null: false
      t.datetime :return_at
      t.timestamps
    end
    # Ficha: os acionamentos de um cliente, do mais recente ao mais antigo (R74).
    add_index :contact_attempts, %i[customer_id contacted_at]
    # Lista e resumo do credor por período (R78, R79); a anulação filtra na própria consulta.
    add_index :contact_attempts, %i[tenant_id contacted_at]
    # Ficha do contrato e restrição de apagar resultado usado: busca pelo resultado.
    add_index :contact_attempts, :result_id

    reversible do |direction|
      direction.up do
        # A permissão 8 (anular acionamentos de outros) foi retirada com a anulação (04, revisão 5): sai dos perfis que a tinham.
        execute "update profiles set permissions = permissions - 'void_others_contact_attempts' where permissions ? 'void_others_contact_attempts'"
        # Credores que já existem recebem a lista inicial (R68).
        values = INITIAL.each_with_index.map do |(name, kind, rule), index|
          key = I18n.transliterate(name).downcase.squish
          "(#{connection.quote(name)}, #{connection.quote(key)}, #{connection.quote(kind)}, #{connection.quote(rule)}, #{index + 1})"
        end.join(", ")
        execute <<~SQL
          insert into contact_results (tenant_id, name, name_key, kind, return_rule, position, created_at, updated_at)
          select t.id, v.name, v.name_key, v.kind, v.return_rule, v.position, now(), now()
          from tenants t cross join (values #{values}) as v(name, name_key, kind, return_rule, position)
        SQL
      end
    end
  end
end
