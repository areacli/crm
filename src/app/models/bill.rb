# Título (parcela, mensalidade, fatura): pertence a um contrato. Vencido ou a vencer é calculado todo dia, e não é gravado (R6).
class Bill < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :customer
  has_many :value_versions, class_name: "BillValueVersion", dependent: :restrict_with_error
  has_many :value_discrepancies, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  enum :status, { active: "active", withdrawn: "withdrawn", paid: "paid" }, validate: true

  scope :overdue, ->(today = Date.current) { active.where(due_date: ...today) }
  scope :upcoming, ->(today = Date.current) { active.where(due_date: today..) }

  def days_overdue(today = Date.current) = [ (today - due_date).to_i, 0 ].max

  # Todo título nasce com a versão 1 do valor (R88). A carga em lote grava a versão no próprio SQL, sem passar por aqui.
  after_create { value_versions.create!(tenant_id: tenant_id, amount_cents: amount_cents, import_id: last_import_id) }

  # Saldo do título: valor vigente menos o alocado, nunca negativo (R89); o que passa do valor é excedente.
  def balance_cents = [ amount_cents - paid_cents, 0 ].max

  # Excedente: quanto o alocado passa do valor vigente quando o valor cai abaixo do que já foi pago (R90). Calculado, nunca gravado.
  def excess_cents = [ paid_cents - amount_cents, 0 ].max
end
