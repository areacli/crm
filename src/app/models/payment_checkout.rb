# Link de checkout (12, parte C, R277): o endereço público /pagar/:token que o cliente abre, sem login, para pagar o cartão e pegar o boleto e o
# Pix já emitidos. O token é aleatório de 256 bits e é o próprio endereço. Nasce só por serviço (`Payments::Checkouts.create`): o back office não
# tem tela para criá-lo. O cartão nunca passa por aqui: cada tentativa de cartão é um instrumento do tipo `card`, e só o resultado fica no link.
#
# Estados: `open` (aceitando pagamento), `card_approved` (o emissor aprovou o cartão; falta a confirmação do fornecedor), `paid`,
# `card_unconfirmed` (não se sabe se o cartão foi cobrado: não se tenta de novo; o credor confere) e `canceled`.
class PaymentCheckout < ApplicationRecord
  include TenantScoped

  MODALITIES = %w[boleto pix card].freeze
  TOKEN_BYTES = 32

  belongs_to :customer, optional: true
  has_many :instruments, class_name: "PaymentInstrument", foreign_key: :checkout_id, inverse_of: :checkout, dependent: :restrict_with_error

  enum :state, { open: "open", card_approved: "card_approved", paid: "paid", card_unconfirmed: "card_unconfirmed", canceled: "canceled" }, prefix: true, validate: true
  enum :environment, { sandbox: "sandbox", production: "production" }, validate: true

  attribute :result, :json, default: -> { {} }

  validates :token, presence: true, uniqueness: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :expires_at, presence: true
  validate :modalities_known
  validate :highlight_offered

  before_validation :generate_token, on: :create

  def to_param = token

  # Aceita acesso: dentro da validade e não cancelado. Link vencido, cancelado ou inexistente se comportam do mesmo jeito na página (404).
  def available?(now = Time.current) = !state_canceled? && expires_at > now

  def offers?(modality) = modalities.include?(modality.to_s)

  # Aceita pagamento de cartão agora: aberto e sem cobrança em curso.
  def card_payable? = offers?("card") && state_open?

  def customer_name = payer_name.to_s

  # O instrumento (boleto ou Pix) do link, na forma entregável (ativo, pago ou vencido).
  def deliverable_instrument(kind)
    instruments.select { |instrument| instrument.kind == kind.to_s && instrument.state.in?(Payments::InstrumentReader::DELIVERABLE_STATES) }.max_by(&:id)
  end

  # R280: o boleto vencido ainda paga até `days_to_write_off` (a conta guarda, padrão 30 dias); o valor mostrado é sempre o emitido.
  def boleto_payable_until(instrument) = instrument.due_on + instrument.account.config.fetch("write_off_days", 30).to_i.days

  def boleto_payable?(instrument, today = Date.current) = today <= boleto_payable_until(instrument)

  def card_instruments = instruments.select(&:card?).sort_by(&:id)

  private
    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(TOKEN_BYTES)
    end

    def modalities_known
      errors.add(:modalities, :invalid) if modalities.blank? || (modalities - MODALITIES).any?
    end

    def highlight_offered
      errors.add(:highlight, :invalid) if highlight.present? && !modalities.include?(highlight)
    end
end
