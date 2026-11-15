# Especificação 16, revisão 1 (R373c): "Trocar fornecedor" cria a integração nova ligada à que ela substitui. Com conexão por autorização, a nova fica
# desativada à espera da conexão, e a anterior continua emitindo; a ligação diz, na página dos meios, que a troca está em andamento e, na volta da
# conexão, qual integração desativar. Uma troca em andamento por integração: o índice único parcial é a regra no banco e também o caminho da
# consulta pela integração substituída. Coluna nula e índice sobre ela: nenhuma linha muda, e o índice só tem as integrações nascidas de uma troca.
class PaymentAccountsReplaces < ActiveRecord::Migration[8.1]
  def change
    add_reference :payment_accounts, :replaces, foreign_key: { to_table: :payment_accounts, on_delete: :nullify }, index: { unique: true, where: "replaces_id is not null" }
  end
end
