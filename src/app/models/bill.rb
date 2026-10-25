# Título (parcela, mensalidade, fatura): pertence a um contrato. Vencido ou a vencer é calculado todo dia, e não é gravado (R6).
class Bill < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :customer

  enum :status, { active: "active", withdrawn: "withdrawn", paid: "paid" }, validate: true

  scope :overdue, ->(today = Date.current) { active.where(due_date: ...today) }
  scope :upcoming, ->(today = Date.current) { active.where(due_date: today..) }

  def days_overdue(today = Date.current) = [ (today - due_date).to_i, 0 ].max

  # Saldo do título: valor menos o pago (R54).
  def balance_cents = amount_cents - paid_cents
end
