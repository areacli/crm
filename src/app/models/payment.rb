# Pagamento recebido por um método de recebimento (antes "canal", 16, MP1a), sempre de um título (MT-22); pendente se o título ainda não está na carteira (R52a).
class Payment < ApplicationRecord
  include TenantScoped

  belongs_to :channel, class_name: "PaymentChannel"
  belongs_to :bill, optional: true
  belongs_to :import, optional: true
  # A promessa que este pagamento paga, ou a que ele contou para (10, R194, DP1); o pagamento de promessa não tem título.
  belongs_to :promise, class_name: "PaymentPromise", optional: true
  has_many :reversals, class_name: "PaymentReversal", dependent: :restrict_with_error

  enum :status, { applied: "applied", pending: "pending", cancelled: "cancelled" }, validate: true

  # Posse (14, R321): ao ficar aplicado a uma fatura, o pagamento grava as operações com quem o contrato estava na data dele.
  before_save :record_possession, if: -> { applied? && bill_id && (will_save_change_to_status? || will_save_change_to_bill_id?) }
  # `prefix` porque "other" e "cash" colidiriam com nomes comuns de método.
  # O meio de pagamento (16, MP1a), do catálogo `PaymentMethod`.
  enum :payment_method, PaymentMethod::ENUM, prefix: :via, validate: true

  # Lê o meio da planilha, sem diferenciar maiúsculas nem acentos (R49); nil quando fora da lista.
  def self.method_from_sheet(raw) = PaymentMethod.from_sheet(raw)

  # O que ainda pode ser estornado (R61).
  def reversible_cents = amount_cents - reversed_cents

  private
    def record_possession
      self.possession_operation_ids = Distributions::Possession.operation_ids(bill&.contract_id, paid_on || Date.current)
    end
end
