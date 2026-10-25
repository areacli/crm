# Configuração do credor: faixas de atraso (R18), tratamento do a vencer (R20) e as políticas de pagamento.
class TenantSetting < ApplicationRecord
  belongs_to :tenant

  # Como os títulos a vencer aparecem nos totais, por credor (R20).
  enum :upcoming_display, { separate: "separate", summed: "summed", detail_only: "detail_only" }, validate: true

  # Políticas de pagamento do credor (R46, R46a, R62a, R64; permissão 14).
  enum :partial_payment_policy, { partial: "partial", credit: "credit" }, prefix: true, validate: true
  enum :withdrawn_payment_policy, { prevails: "prevails", credit: "credit" }, prefix: true, validate: true
  enum :withdrawn_reversal_policy, { reopen: "reopen", withdrawn: "withdrawn" }, prefix: true, validate: true
  enum :reversal_month_policy, { reversal: "reversal", payment: "payment" }, prefix: true, validate: true

  PAYMENT_POLICIES = %w[partial_payment_policy withdrawn_payment_policy withdrawn_reversal_policy reversal_month_policy].freeze

  # Faixas iniciais de atraso, em dias: de 1 a 30, de 31 a 60, de 61 a 90, de 91 a 180, de 181 a 360 e mais de 360.
  DEFAULT_BRACKETS = [
    { from: 1, to: 30 }, { from: 31, to: 60 }, { from: 61, to: 90 }, { from: 91, to: 180 }, { from: 181, to: 360 }, { from: 361, to: nil }
  ].freeze
end
