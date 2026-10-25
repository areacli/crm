# Instrumento de pagamento emitido (12, R271): um boleto ou um Pix, de uma conta de pagamento. Na parte C o cartão também vira instrumento: uma
# cobrança por tentativa de pagamento no checkout (sem arquivo, sem linha digitável; só o identificador do fornecedor e o resultado). Os estados são nossos (R258): `emitting` (a emissão
# está em curso), `active`, `paid`, `expired`, `canceled` e `failed`; cada fornecedor traduz o dele para estes. O PDF do boleto e a imagem do
# QR Code do Pix ficam em Active Storage (disco), com o SHA-256 guardado (R273). Nunca se guarda o link do fornecedor. A referência ao objeto
# cobrado é opaca (tipo e número): o vínculo com título, promessa ou acordo vem quando cada escopo pedir.
class PaymentInstrument < ApplicationRecord
  include TenantScoped

  belongs_to :account, class_name: "PaymentAccount", inverse_of: :instruments
  belongs_to :customer, optional: true
  belongs_to :checkout, class_name: "PaymentCheckout", optional: true, inverse_of: :instruments
  # O pagamento que a baixa gerou no CRM (parte D): o instrumento pago fica ligado a ele, para o estorno achar de onde saiu o valor.
  belongs_to :payment, optional: true

  enum :kind, { boleto: "boleto", pix: "pix", card: "card" }, validate: true
  enum :state, { emitting: "emitting", active: "active", paid: "paid", expired: "expired", canceled: "canceled", failed: "failed" }, prefix: true, validate: true

  has_one_attached :boleto_pdf, dependent: :purge_later
  has_one_attached :pix_qr_png, dependent: :purge_later

  # Nosso identificador (R272): letras e números, de 26 a 35 caracteres (o `txid` do Pix tem essa regra; serve também ao boleto).
  CUSTOM_ID_FORMAT = /\A[a-zA-Z0-9]{26,35}\z/

  validates :custom_id, format: { with: CUSTOM_ID_FORMAT }, uniqueness: { scope: :tenant_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :due_on, presence: true
  validate :account_of_same_tenant
  validate :checkout_of_same_tenant

  scope :with_state, ->(*states) { where(state: states) }

  # Pago nunca é cancelado nem apagado (R276).
  def final? = state_paid?
  def cancelable? = state_active?

  def fail!(reason)
    update!(state: "failed", failure_reason: reason.to_s.truncate(300))
  end

  private
    def checkout_of_same_tenant
      errors.add(:checkout, :other_tenant) if checkout && checkout.tenant_id != tenant_id
    end

    def account_of_same_tenant
      errors.add(:account, :other_tenant) if account && account.tenant_id != tenant_id
    end
end
