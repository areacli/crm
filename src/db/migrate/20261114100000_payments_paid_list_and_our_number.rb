# Especificação 12, revisão 4 (incremento 18, adaptador Bradesco): a lista de pagos ao lado do webhook (R284c), o nosso número reservado pelo CRM
# antes da chamada (R284f) e o registro do cadastro do webhook no fornecedor (R284g). Só colunas nulas: nenhuma linha muda e nenhum índice entra
# (a reserva é pela chave primária; o instrumento continua achado pelo identificador externo na integração).
class PaymentsPaidListAndOurNumber < ActiveRecord::Migration[8.1]
  def change
    change_table :payment_accounts, bulk: true do |t|
      t.datetime :paid_listed_until
      t.bigint :our_number_last
      t.datetime :webhook_registered_at
      t.string :webhook_registered_url, limit: 300
    end
    add_column :payment_instruments, :our_number, :string, limit: 20
  end
end
