# Instrumento de pagamento emitido (12, R271): um boleto ou um Pix, de uma conta de pagamento. Na parte C o cartão também vira instrumento: uma
# cobrança por tentativa de pagamento no checkout (sem arquivo, sem linha digitável; só o identificador do fornecedor e o resultado). Os estados são nossos (R258): `emitting` (a emissão
# está em curso), `active`, `paid`, `expired`, `canceled` e `failed`; cada fornecedor traduz o dele para estes. O PDF do boleto e a imagem do
# QR Code do Pix ficam em Active Storage (disco), com o SHA-256 guardado (R273). Nunca se guarda o link do fornecedor.
#
# Desde a 16 (camada 20), todo instrumento tem um objeto: um título (fatura ou título de acordo) ou uma promessa, exatamente um (restrição do
# banco). `open` é o "vigente" da 16: verdadeiro enquanto o instrumento ainda pode ser pago e não foi (emitindo, ativo, cancelamento pendente,
# e o vencido até passarem os dias para baixa); o índice único parcial sobre `open` garante um vigente por objeto e meio de pagamento (R378).
class PaymentInstrument < ApplicationRecord
  include TenantScoped

  belongs_to :account, class_name: "PaymentAccount", inverse_of: :instruments
  belongs_to :customer, optional: true
  belongs_to :checkout, class_name: "PaymentCheckout", optional: true, inverse_of: :instruments
  # O pagamento que a baixa gerou no CRM (parte D): o instrumento pago fica ligado a ele, para o estorno achar de onde saiu o valor.
  belongs_to :payment, optional: true
  belongs_to :bill, optional: true
  belongs_to :promise, class_name: "PaymentPromise", optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :canceled_by, class_name: "User", optional: true
  belongs_to :instrument_batch, optional: true
  belongs_to :replaced_by, class_name: "PaymentInstrument", optional: true

  enum :kind, { boleto: "boleto", pix: "pix", card: "card" }, validate: true
  enum :state, { emitting: "emitting", active: "active", paid: "paid", expired: "expired", canceled: "canceled", failed: "failed", cancel_pending: "cancel_pending" },
       prefix: true, validate: true
  # Origem do pedido (16, R394): a ficha, o registro da promessa ou do acordo, o lote, a régua, a reemissão automática, ou o serviço (console, testes, demonstração).
  enum :origin, { customer_page: "customer_page", registration: "registration", batch: "batch", rule: "rule", reissue: "reissue", service: "service" },
       prefix: true, validate: { allow_nil: true }

  # Estados que encerram o instrumento: deixa de ser vigente.
  CLOSED_STATES = %w[paid canceled failed].freeze
  OPEN_STATES = %w[emitting active cancel_pending].freeze

  has_one_attached :boleto_pdf, dependent: :purge_later
  has_one_attached :pix_qr_png, dependent: :purge_later

  # Nosso identificador (R272): letras e números, de 26 a 35 caracteres (o `txid` do Pix tem essa regra; serve também ao boleto).
  CUSTOM_ID_FORMAT = /\A[a-zA-Z0-9]{26,35}\z/

  validates :custom_id, format: { with: CUSTOM_ID_FORMAT }, uniqueness: { scope: :tenant_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :due_on, presence: true
  validate :account_of_same_tenant
  validate :checkout_of_same_tenant
  validate :one_object

  before_save :close_when_final

  scope :with_state, ->(*states) { where(state: states) }

  # Pago nunca é cancelado nem apagado (R276).
  def final? = state_paid?
  def cancelable? = state_active?

  # O objeto cobrado: o título ou a promessa.
  def object = bill || promise

  def object=(record)
    self.bill = record.is_a?(Bill) ? record : nil
    self.promise = record.is_a?(PaymentPromise) ? record : nil
  end

  def fail!(reason)
    update!(state: "failed", failure_reason: reason.to_s.truncate(300))
  end

  private
    # Vigente: emitindo, ativo e cancelamento pendente sempre; o vencido continua como estava até a tarefa diária fechá-lo; os finais nunca.
    def close_when_final
      if CLOSED_STATES.include?(state) then self.open = false
      elsif OPEN_STATES.include?(state) then self.open = true
      end
    end

    def one_object
      errors.add(:base, :one_object) unless [ bill_id || bill, promise_id || promise ].compact.size == 1
      errors.add(:base, :other_tenant) if object && object.tenant_id != tenant_id
    end

    def checkout_of_same_tenant
      errors.add(:checkout, :other_tenant) if checkout && checkout.tenant_id != tenant_id
    end

    def account_of_same_tenant
      errors.add(:account, :other_tenant) if account && account.tenant_id != tenant_id
    end
end
