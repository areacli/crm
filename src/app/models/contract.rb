# Contrato: obrigatório para todo título (MT-11), com um ou mais clientes do mesmo credor (MT-12). Sem código quando criado por
# omissão (MT-14).
class Contract < ApplicationRecord
  include TenantScoped

  belongs_to :segment, optional: true
  has_many :contract_segments, dependent: :delete_all
  has_many :contract_customers, dependent: :destroy
  has_many :customers, through: :contract_customers
  has_many :bills, dependent: :restrict_with_error
  has_many :credits, dependent: :restrict_with_error

  # Crédito do contrato (R55b): é do contrato, não de um cliente. O crédito disponível do contrato (11, R223, R232b): o que pode ser usado em acordo, em título de acordo ou transferido. O aguardando alocação (reversão) e o bloqueado (estorno à
  # espera do gestor) não contam como disponíveis (R232b, R233).
  def credit_cents = credits.where(bucket: "available").sum(:amount_cents)

  # O saldo de cada estado: { "available" => ., "awaiting" => ., "blocked" => . }.
  def credit_balances = Credit::BUCKET_ZERO.merge(credits.group(:bucket).sum(:amount_cents))

  def label = code.presence || "Contrato sem código"
end
