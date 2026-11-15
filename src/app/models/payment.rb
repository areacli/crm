# Pagamento de um título (MT-22), pendente se o título ainda não está na carteira (R52a). "Como foi pago": o meio, o fornecedor que deu o
# identificador, a conta nele e o identificador; o fornecedor, a conta e o identificador o identificam no credor (R48; 03, revisão 12, que tirou
# o método de recebimento).
class Payment < ApplicationRecord
  include TenantScoped

  # Sistema pai (17, R416, R418): o da linha que trouxe o pagamento; o CRM quando o pagamento nasce aqui (uso de crédito do contrato).
  belongs_to :source_system
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
  enum :payment_method, PaymentMethod::ALL_ENUM, prefix: :via, validate: true

  validates :provider, :provider_name, :account_key, :account_code, presence: true, length: { maximum: 100 }

  # Lê o meio da planilha, sem diferenciar maiúsculas nem acentos (R49); nil quando fora da lista.
  def self.method_from_sheet(raw) = PaymentMethod.from_sheet(raw)

  validates :external_bill_id, length: { maximum: 100 }
  before_validation :assume_source_system, on: :create

  # O que ainda pode ser estornado (R61).
  def reversible_cents = amount_cents - reversed_cents

  # O fornecedor como a tela o mostra (o nome do fornecedor com integração, senão o que a planilha trouxe).
  def provider_label = PaymentProvider.label(provider, provider_name)

  # "Como foi pago", numa linha: meio, fornecedor, conta e identificador.
  def how_paid = [ PaymentMethod.label(payment_method), provider_label, account_code, identifier ].join(" · ")

  private
    # Quem não informa o sistema: o uso de crédito do contrato é do CRM; o resto, do sistema padrão do credor. A importação sempre informa.
    def assume_source_system
      return if source_system_id || tenant_id.nil?

      own = via_contract_credit?
      self.source_system = own ? SourceSystem.crm_of(tenant_id) : SourceSystem.default_of(tenant_id)
    end

    def record_possession
      self.possession_operation_ids = Distributions::Possession.operation_ids(bill&.contract_id, paid_on || Date.current)
    end
end
