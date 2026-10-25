# Lançamento no livro do crédito do contrato (MT-22): só inserção, o saldo é a soma. Positivo na origem (excedente, título já pago,
# título retirado, "crédito sem baixar", transferência recebida) e negativo no estorno e na transferência enviada.
class Credit < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :payment, optional: true
  belongs_to :user, optional: true
  belongs_to :related_contract, class_name: "Contract", optional: true
  belongs_to :agreement, optional: true
  # O título em que o crédito foi usado (a ficha, 11, R232b, e o acordo sobre acordo).
  belongs_to :bill, optional: true

  # `moved`: a passagem entre estados (11, R233, R239): um lançamento negativo num balde e um positivo noutro; `manager`: o lançamento do gestor ao decidir um estorno à espera (AH2).
  enum :kind, { entry: "entry", reversal: "reversal", transfer_out: "transfer_out", transfer_in: "transfer_in", used: "used", restored: "restored", moved: "moved", manager: "manager" }, validate: true
  enum :reason, { already_paid: "already_paid", excess: "excess", withdrawn: "withdrawn", without_settling: "without_settling",
                  reversed: "reversed", transfer: "transfer", agreement: "agreement", renegotiated: "renegotiated", canceled_title: "canceled_title",
                  settlement_reversed: "settlement_reversed", reversal_waiting: "reversal_waiting", manager_entry: "manager_entry", used_on_title: "used_on_title",
                  allocated: "allocated", during_reversal: "during_reversal" }, prefix: :because, validate: true
  # Os estados do crédito do contrato (dominio.md): disponível, aguardando alocação (reversão, R239) e bloqueado (estorno à espera do gestor, AK2). O usado e o transferido
  # são lançamentos negativos; o saldo de cada balde é a soma.
  enum :bucket, { available: "available", awaiting: "awaiting", blocked: "blocked" }, prefix: :bucket, validate: true

  scope :available, -> { where(bucket: "available") }

  BUCKET_ZERO = { "available" => 0, "awaiting" => 0, "blocked" => 0 }.freeze

  validates :amount_cents, numericality: { other_than: 0, only_integer: true }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }

  # O livro não se corrige: um lançamento gravado não muda nem se apaga.
  def readonly? = persisted? || super
end
