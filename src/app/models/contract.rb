# Contrato: obrigatório para todo título (MT-11), com um ou mais clientes do mesmo credor (MT-12). Sem código quando criado por
# omissão (MT-14).
class Contract < ApplicationRecord
  include TenantScoped

  # Sistema pai (17, R403): nunca muda. Em sistema de id próprio, `external_id` é o id do contrato lá; em chave natural fica vazio e vale o código.
  belongs_to :source_system
  belongs_to :tier, optional: true
  has_many :contract_tiers, dependent: :delete_all
  has_many :contract_customers, dependent: :destroy
  has_many :customers, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error
  has_many :credits, dependent: :restrict_with_error

  attr_readonly :source_system_id
  validates :external_id, length: { maximum: 100 }
  # Quem não informa o sistema cria o contrato no sistema padrão do credor; a confirmação da carga sempre informa.
  before_validation(on: :create) { self.source_system ||= SourceSystem.default_of(tenant_id) if tenant_id }

  # Crédito do contrato (R55b): é do contrato, não de um cliente. O crédito disponível do contrato (11, R223, R232b): o que pode ser usado em acordo, em título de acordo ou transferido. O aguardando alocação (reversão) e o bloqueado (estorno à
  # espera do gestor) não contam como disponíveis (R232b, R233).
  def credit_cents = credits.where(bucket: "available").sum(:amount_cents)

  # O saldo de cada estado: { "available" => ., "awaiting" => ., "blocked" => . }.
  def credit_balances = Credit::BUCKET_ZERO.merge(credits.group(:bucket).sum(:amount_cents))

  def label = code.presence || "Contrato sem código"
end
