# Régua, etapa 1 (21; 13, revisões 7 e 8; plano técnico da camada 23): as datas de cobrança do título, o episódio de atraso, a data de início do
# contrato (01, `inicio_contrato`) e o sorteio do cliente.
class ArrearsEpisodesAndCatalogDates < ActiveRecord::Migration[8.1]
  def up
    # O dia (de Brasília) em que o título saiu de cobrança e em que voltou a ela, gravados pelo modelo (`Bill`, ponto único da mudança de estado).
    add_column :bills, :closed_on, :date
    add_column :bills, :reopened_on, :date
    # Os títulos de hoje que já saíram de cobrança: o pago no dia do pagamento; o retirado no dia da retirada; o renegociado e o cancelado no dia da
    # última mudança (a melhor data que existe). O agendado nunca foi cobrado e fica sem data.
    execute <<~SQL
      update bills set closed_on = case
          when status = 'paid' then coalesce(paid_on, (updated_at at time zone '#{zone}')::date)
          when status = 'withdrawn' then (coalesce(withdrawn_at, updated_at) at time zone '#{zone}')::date
          else (updated_at at time zone '#{zone}')::date
        end
      where status in ('paid', 'withdrawn', 'renegotiated', 'canceled')
    SQL

    # Data de início do contrato no sistema do credor (01, coluna `inicio_contrato`; atributo `iniciado há` da 13).
    add_column :contracts, :started_on, :date
    add_column :import_rows, :started_on, :date

    # Sorteio (13, revisão 7, R256): 0 a 99, fixo por cliente, sorteado na criação; o PostgreSQL calcula o padrão linha a linha para os clientes de hoje.
    add_column :customers, :draw, :smallint, null: false, default: -> { "(floor(random() * 100))::smallint" }
    add_check_constraint :customers, "draw between 0 and 99", name: "customers_draw_range"

    # Episódio de atraso de um contrato ou de um cliente (21, R434): do início da ilha de atraso dos títulos até o fim, um aberto por sujeito.
    create_table :arrears_episodes do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :subject_type, null: false, limit: 20
      t.bigint :subject_id, null: false
      t.date :started_on, null: false
      t.date :ended_on
      t.timestamps
    end
    add_check_constraint :arrears_episodes, "subject_type in ('contracts', 'customers')", name: "arrears_episodes_subject_type"
    add_check_constraint :arrears_episodes, "ended_on is null or ended_on >= started_on - 1", name: "arrears_episodes_dates"
    add_index :arrears_episodes, %i[tenant_id subject_type subject_id], unique: true, where: "ended_on is null", name: "index_arrears_episodes_open"
    add_index :arrears_episodes, %i[subject_type subject_id started_on], name: "index_arrears_episodes_by_subject"

    Operations::Rls.install!(connection)
  end

  def down
    drop_table :arrears_episodes
    remove_check_constraint :customers, name: "customers_draw_range"
    remove_column :customers, :draw
    remove_column :import_rows, :started_on
    remove_column :contracts, :started_on
    remove_column :bills, :reopened_on
    remove_column :bills, :closed_on
  end

  private
    def zone = BrDate.zone_name
end
