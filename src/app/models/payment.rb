# Pagamento recebido por um canal, sempre de um título (MT-22); pendente se o título ainda não está na carteira (R52a).
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
  enum :payment_method, { pix: "pix", boleto: "boleto", credit_card: "credit_card", debit_card: "debit_card", transfer: "transfer", cash: "cash",
                          other: "other" }, prefix: :via, validate: true

  # Lê o meio da planilha, sem diferenciar maiúsculas nem acentos (R49); nil quando fora da lista.
  METHOD_ALIASES = {
    "pix" => "pix", "boleto" => "boleto", "cartaodecredito" => "credit_card", "cartaocredito" => "credit_card",
    "cartaododebito" => "debit_card", "cartaodebito" => "debit_card", "cartaodedebito" => "debit_card", "transferencia" => "transfer",
    "dinheiro" => "cash", "outro" => "other"
  }.freeze

  def self.method_from_sheet(raw) = METHOD_ALIASES[FoldedText.fold(raw.to_s).delete(" -_")]

  # O que ainda pode ser estornado (R61).
  def reversible_cents = amount_cents - reversed_cents

  private
    def record_possession
      self.possession_operation_ids = Distributions::Possession.operation_ids(bill&.contract_id, paid_on || Date.current)
    end
end
