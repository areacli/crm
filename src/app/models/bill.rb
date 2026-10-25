# Título (parcela, mensalidade, fatura): pertence a um contrato. Vencido ou a vencer é calculado todo dia, e não é gravado (R6).
class Bill < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :customer
  # Título de acordo (a entrada e as parcelas) ou da quebra: pertence a um acordo (11, R225).
  belongs_to :agreement, optional: true
  # Título de estorno (11, R233): título comum do cliente criado pelo CRM, numerado a partir do acordo de origem e fora dele.
  belongs_to :origin_agreement, class_name: "Agreement", optional: true
  has_many :value_versions, class_name: "BillValueVersion", dependent: :restrict_with_error
  has_many :value_discrepancies, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  # `renegotiated`: título original de um acordo efetivado (11, R225); `scheduled`: título de acordo que existe, mas só passa a ser cobrado com a efetivação
  # (R221); `canceled`: título de acordo cancelado (quebra antes da efetivação, título único, reversão).
  enum :status, { active: "active", withdrawn: "withdrawn", paid: "paid", renegotiated: "renegotiated", scheduled: "scheduled", canceled: "canceled" }, validate: true
  enum :kind, { common: "common", agreement: "agreement", break: "break", reversal: "reversal" }, prefix: :kind, validate: true

  scope :agreement_titles, -> { where.not(kind: "common") }
  # Os títulos que são do acordo (a entrada, as parcelas e o título da quebra); o título de estorno é comum e fica fora dele (R233, AH1).
  scope :of_agreement, -> { where(kind: %w[agreement break]) }
  scope :overdue, ->(today = Date.current) { active.where(due_date: ...today) }
  scope :upcoming, ->(today = Date.current) { active.where(due_date: today..) }

  # O título de acordo que está em cobrança ou que ainda vai ser cobrado (a vencer): tem devido calculado pelos parâmetros do acordo.
  def status_in_collection? = active? || scheduled?

  # Tem devido calculado pelos parâmetros congelados de um acordo: título de acordo, da quebra ou de estorno.
  def ledgered? = !kind_common?

  def days_overdue(today = Date.current) = [ (today - due_date).to_i, 0 ].max

  # Todo título nasce com a versão 1 do valor (R88). A carga em lote grava a versão no próprio SQL, sem passar por aqui.
  after_create { value_versions.create!(tenant_id: tenant_id, amount_cents: amount_cents, import_id: last_import_id) }

  # Saldo do título: valor vigente menos o alocado, nunca negativo (R89); o que passa do valor é excedente.
  def balance_cents = [ amount_cents - paid_cents, 0 ].max

  # Excedente: quanto o alocado passa do valor vigente quando o valor cai abaixo do que já foi pago (R90). Calculado, nunca gravado.
  def excess_cents = [ paid_cents - amount_cents, 0 ].max
end
