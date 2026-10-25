# Título de uma promessa com o valor de cada componente na data prometida (R186, R187). `paid` guarda o que os pagamentos que contam já
# alocaram em cada componente; `held` diz que a promessa prende o título (R185); `removed_at` marca o que saiu da promessa (R202, R202a).
class PaymentPromiseBill < ApplicationRecord
  # Componente => coluna, na ordem em que um pagamento os cobre (Charges::ORDER).
  COLUMNS = { "interest" => :interest_cents, "fine" => :fine_cents, "fees" => :fees_cents, "correction" => :correction_cents, "principal" => :principal_cents }.freeze

  belongs_to :promise, class_name: "PaymentPromise", inverse_of: :promise_bills
  belongs_to :bill

  def removed? = removed_at.present?

  # { componente => centavos } do valor congelado, só os componentes com valor.
  def components = COLUMNS.to_h { |component, column| [ component, self[column] ] }.select { |_, cents| cents.positive? }

  # O que falta cobrir em cada componente: o congelado menos o que os pagamentos que contam já alocaram.
  def remaining = components.to_h { |component, cents| [ component, cents - paid.fetch(component, 0) ] }.select { |_, cents| cents.positive? }

  def paid_cents = paid.values.sum
end
