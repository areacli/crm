# Versão do valor original de um título (R88): cada valor que o título já teve, com a importação, a data e quem confirmou. A vigente é a
# última. Só inserção; `bills.amount_cents` é a cópia da vigente, gravada na mesma transação.
class BillValueVersion < ApplicationRecord
  include TenantScoped

  belongs_to :bill
  belongs_to :import, optional: true
  belongs_to :user, optional: true

  scope :in_order, -> { order(:id) }

  # O histórico não se corrige: uma versão gravada não muda nem se apaga.
  def readonly? = persisted? || super
end
