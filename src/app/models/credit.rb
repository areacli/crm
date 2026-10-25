# Lançamento no livro do crédito do contrato (MT-22): só inserção, o saldo é a soma. Positivo na origem (excedente, título já pago,
# título retirado, "crédito sem baixar", transferência recebida) e negativo no estorno e na transferência enviada.
class Credit < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :payment, optional: true
  belongs_to :user, optional: true
  belongs_to :related_contract, class_name: "Contract", optional: true

  enum :kind, { entry: "entry", reversal: "reversal", transfer_out: "transfer_out", transfer_in: "transfer_in" }, validate: true
  enum :reason, { already_paid: "already_paid", excess: "excess", withdrawn: "withdrawn", without_settling: "without_settling",
                  reversed: "reversed", transfer: "transfer" }, prefix: :because, validate: true

  validates :amount_cents, numericality: { other_than: 0, only_integer: true }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }

  # O livro não se corrige: um lançamento gravado não muda nem se apaga.
  def readonly? = persisted? || super
end
