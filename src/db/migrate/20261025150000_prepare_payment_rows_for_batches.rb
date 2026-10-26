# Importação de pagamentos e estornos em lotes (decisão 0021, parte 2): a ordem do fluxo (data, prioridade, linha) fica gravada na própria preparação
# (`rank`), os pagamentos pendentes entram nela como linhas (`pending_payment_id`) e cada lote é uma consulta por chave `(paid_on, rank, line)`. O cursor e o
# resumo parcial da confirmação ficam em `imports.batch_state`, na mesma transação do lote. Custo na escrita: a preparação é escrita uma vez por carga e
# apagada ao fim (medido na V4-lote de pagamentos, no plano técnico da revisão).
class PreparePaymentRowsForBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_rows, :rank, :integer, limit: 2, null: false, default: 3
    add_column :payment_rows, :pending_payment_id, :bigint
    add_column :imports, :batch_state, :jsonb
    remove_index :payment_rows, %i[import_id ok paid_on line], name: "index_payment_rows_on_import_id_and_ok_and_paid_on_and_line"
    add_index :payment_rows, %i[import_id ok paid_on rank line], name: "index_payment_rows_on_stream_order"
    add_index :payment_rows, %i[import_id line], unique: true, name: "index_payment_rows_on_import_id_and_line"
  end
end
