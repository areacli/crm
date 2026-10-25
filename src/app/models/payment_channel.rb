# Canal de recebimento do credor: por onde o dinheiro entrou (R45). O tipo é só leitura; o código é o que a planilha traz.
class PaymentChannel < ApplicationRecord
  include TenantScoped

  # O segredo que assina o webhook deste canal fica cifrado no banco.
  encrypts :webhook_secret

  has_many :payments, foreign_key: :channel_id, inverse_of: :channel, dependent: :restrict_with_error
  has_many :webhook_events, foreign_key: :channel_id, inverse_of: :channel, dependent: :delete_all

  enum :kind, { account: "account", agreement: "agreement", card: "card" }, validate: true

  normalizes :code, :description, with: ->(value) { value.to_s.strip }

  validates :code, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validates :description, presence: true, length: { maximum: 200 }
  validates :webhook_adapter, inclusion: { in: ->(_) { Payments::Gateway.names } }

  scope :active, -> { where(active: true) }

  # R45 (revisão 7): o código só muda enquanto o canal não tem pagamento; o canal com pagamento só é desativado, nunca apagado.
  def used? = payments.exists?

  def webhook_enabled? = webhook_secret.present?

  # Gera (ou troca) o segredo do webhook e o devolve em claro, uma única vez.
  def regenerate_webhook_secret!
    secret = SecureRandom.base58(40)
    update!(webhook_secret: secret)
    secret
  end
end
