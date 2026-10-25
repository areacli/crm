# Promessa de pagamento (10): o vínculo de 1 a n títulos de um contrato, feito por um cliente, com um meio de pagamento, uma data e um valor
# (R183 a R187). Valor, políticas e alçada ficam congelados no registro; não há isenção nem desconto (premissa do Paulo, 21/10/2026).
class PaymentPromise < ApplicationRecord
  include TenantScoped

  STATES = %w[pending open fulfilled fulfilled_late broken canceled refused not_approved].freeze
  # Estados em que a promessa prende os títulos (R185).
  HOLDING = %w[pending open].freeze
  # Estados de quem não cumpriu, em que o título só volta a uma promessa nova depois da carência (R188).
  GRACE_STATES = %w[broken canceled refused not_approved].freeze

  belongs_to :customer
  belongs_to :contract
  belongs_to :contact_attempt
  belongs_to :user, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :segment, optional: true
  has_many :promise_bills, class_name: "PaymentPromiseBill", foreign_key: :promise_id, inverse_of: :promise, dependent: :delete_all
  has_many :bills, through: :promise_bills

  # `prefix` porque `open` colidiria com o método do Kernel.
  enum :state, STATES.index_with(&:itself), prefix: :state, validate: true
  enum :payment_method, Payment.payment_methods, prefix: :via, validate: true

  scope :holding, -> { where(state: HOLDING) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # O último dia em que o pagamento ainda é esperado: a data prometida mais a tolerância congelada (DP12).
  def deadline = promised_on + policies.fetch("tolerance_days", 3).to_i.days

  # Dias entre o contato e a data prometida, que a alçada compara (R190).
  def days_asked = (promised_on - contacted_on).to_i

  def holding? = HOLDING.include?(state)

  def closed? = !holding?

  def label = number.presence || "Sem número"

  # Os títulos que ainda contam no valor (os que saíram da promessa não contam, R202).
  def active_bills = promise_bills.reject(&:removed?)

  # Percentual pago, arredondado (R197: "pago 13%" para R$ 200,00 de R$ 1.579,93).
  def paid_percent_value = total_cents.positive? ? (paid_cents * 100.0 / total_cents).round : 0

  # Encerra a promessa: o estado final, o motivo (quando há), o percentual pago, e os títulos ficam livres (R192, R193, R197, R200). Registra a mudança.
  def close!(new_state, reason: nil, actor: nil)
    before = state
    ApplicationRecord.transaction do
      update!(state: new_state, closed_at: Time.current, reason: reason, paid_percent: paid_percent_value)
      promise_bills.update_all(held: false)
      Change.create!(tenant_id: tenant_id, user: actor, subject_type: "payment_promise", subject_id: id, event: "state_changed", field: "state", before: before, after: new_state, note: reason)
    end
    self
  end

  # O evento de invalidação sai depois da gravação (a ficha do cliente e a lista de pendentes se refazem sozinhas).
  after_commit :announce_change, on: %i[create update]

  private
    def announce_change = Promises::Broadcast.changed(tenant, contract.customer_ids)
end
