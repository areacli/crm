# A liquidação estornada na reversão (11, R239, R60): o pagamento passa a crédito aguardando alocação sem arquivo do canal. `applied_cents` continua o que foi aplicado na
# confirmação (o recuperado dos meses anteriores não muda, R64); o que já voltou a crédito fica em `moved_to_credit_cents`, e o crédito efetivo do pagamento é
# `credit_cents + moved_to_credit_cents`. O estorno bancário usa o efetivo para saber quanto sai do crédito e quanto do título.
class AddMovedToCreditToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :moved_to_credit_cents, :bigint, null: false, default: 0
    add_check_constraint :payments, "moved_to_credit_cents >= 0", name: "payments_moved_to_credit"
  end
end
