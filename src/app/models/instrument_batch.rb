# Lote de emissão de instrumentos (16, R384): sobre um segmento, um tipo de objeto e um meio de pagamento, com a conferência antes e a emissão
# em segundo plano depois. Copia o lote da distribuição (`DistributionBatch`): conferir, conferido, confirmado, descartado ou falhou.
class InstrumentBatch < ApplicationRecord
  include TenantScoped

  # A conferência vale por 30 minutos (como a da distribuição): depois, confere-se de novo.
  VALID_FOR = 30.minutes

  belongs_to :created_by, class_name: "User"
  belongs_to :confirmed_by, class_name: "User", optional: true
  belongs_to :segment
  belongs_to :task_run, optional: true
  has_many :instruments, class_name: "PaymentInstrument", dependent: :nullify

  enum :object_kind, { bills: "bills", agreement_bills: "agreement_bills", promises: "promises" }, validate: true
  enum :payment_method, { boleto: "boleto", pix: "pix", card: "card" }, prefix: :via, validate: true
  enum :due_mode, { date: "date", days: "days" }, prefix: true, validate: true
  enum :status, { checking: "checking", checked: "checked", confirmed: "confirmed", discarded: "discarded", failed: "failed" }, validate: true

  validates :due_on, presence: true, if: :due_mode_date?
  validates :due_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 120 }, if: :due_mode_days?

  def expired?(now = Time.current) = checked? && checked_at && checked_at + VALID_FOR < now
end
