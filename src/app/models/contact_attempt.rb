# Acionamento: uma tentativa de contato com um cliente (R69). Registro imutável do que aconteceu: não se edita, não se anula e não se apaga
# (04, revisão 5); quem errou registra um acionamento novo com a observação. Cada registro avisa o credor pelo WebSocket para as telas refazerem o trecho (sem polling).
class ContactAttempt < ApplicationRecord
  include TenantScoped

  # Lista fixa de canais (R65).
  CHANNELS = %w[phone whatsapp sms email letter in_person other].freeze

  belongs_to :customer
  belongs_to :contract, optional: true
  belongs_to :user, optional: true
  belongs_to :result, class_name: "ContactResult"
  # A promessa que nasceu deste acionamento, se houve (10, R203).
  has_one :promise, class_name: "PaymentPromise", dependent: :restrict_with_error

  enum :channel, CHANNELS.index_with(&:itself), prefix: :via, validate: true
  # Cópia do tipo do resultado no momento do registro (o tipo nunca muda, R66).
  enum :result_kind, ContactResult::KINDS, prefix: :result, validate: true

  scope :recent, -> { order(contacted_at: :desc, id: :desc) }

  # Histórico da ficha (R74): do contato mais recente ao mais antigo, 20 por vez. Consulta: `contact_attempts (customer_id, contacted_at)`.
  def self.history_for(customer, page:)
    Pagination.new(where(customer_id: customer.id).includes(:result, :user, :contract, :promise).recent, page: page, per_page: 20)
  end

  after_commit :announce_change, on: :create

  # Imutável depois de gravado.
  def readonly? = persisted? || super

  private
    # Evento pequeno de invalidação: quem tem a lista (canal do credor) ou a ficha (canal do cliente) aberta busca o trecho de novo (decisão 0020).
    def announce_change
      message = { event: "contact-attempts-changed", customer_id: customer_id }
      ContactAttemptsChannel.broadcast_to(tenant, message)
      ContactAttemptsChannel.broadcast_to(customer, message)
    end
end
