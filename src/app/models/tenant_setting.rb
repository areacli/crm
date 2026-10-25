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

  # Divergência de valor (R94, permissão 14): seguir o valor novo (padrão) ou manter o valor vigente e só registrar.
  enum :discrepancy_policy, { follow: "follow", keep: "keep" }, prefix: true, validate: true

  # Correção na tela ou carga: qual vale (06, R117). Padrão: a tela prevalece.
  enum :correction_policy, { screen: "screen", load: "load" }, prefix: true, validate: true

  # Prazo de guarda dos dados do cliente, em anos (07, R136): mínimo 1, padrão 5 (PG1).
  validates :retention_years, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 50 }

  # Produto do contrato no segmento (R150, R151, DS1): pelo título mais atrasado (padrão), pelo maior saldo ou por qualquer título.
  enum :segment_product_policy, { most_overdue: "most_overdue", largest_balance: "largest_balance", any_bill: "any_bill" }, prefix: true, validate: true

  # Encargos do credor (09): parâmetros que os segmentos herdam (R160, R207a) e as políticas que mudam o cálculo (R165, R180 a R182).
  enum :charge_index, { none: "none", ipca: "ipca", inpc: "inpc", igpm: "igpm" }, prefix: true, validate: true
  enum :charge_days_convention, { calendar: "calendar", thirty: "thirty" }, prefix: true, validate: true
  enum :charge_fine_base, { corrected: "corrected", face: "face" }, prefix: true, validate: true
  enum :missing_index_policy, { closed_only: "closed_only", last_prorated: "last_prorated" }, prefix: true, validate: true
  enum :default_interest_form, { simple: "simple", compound: "compound" }, prefix: true, validate: true
  enum :negative_index_policy, { floor: "floor", always: "always", ignore: "ignore" }, prefix: true, validate: true
  enum :old_legal_interest_policy, { selic: "selic", one_percent: "one_percent", none: "none" }, prefix: true, validate: true
  enum :surcharge_comparison_policy, { before: "before", after: "after" }, prefix: true, validate: true
  validates :charge_fine_pct, :charge_interest_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Os campos que a conferência do impacto leva e a confirmação grava (parâmetros e políticas de encargos).
  CHARGE_PARAMS = %w[charge_fine_pct charge_interest_pct charge_index charge_days_convention charge_fine_base].freeze
  CHARGE_POLICIES = %w[missing_index_policy default_interest_form negative_index_policy old_legal_interest_policy surcharge_comparison_policy].freeze
  # A política "comparação dos acréscimos" não muda valores: grava sem mudar o valor atualizado (R182); as outras passam pela conferência.
  CHARGE_FIELDS = (CHARGE_PARAMS + CHARGE_POLICIES).freeze

  PAYMENT_POLICIES = %w[partial_payment_policy withdrawn_payment_policy withdrawn_reversal_policy reversal_month_policy].freeze

  # Faixas iniciais de atraso, em dias: de 1 a 30, de 31 a 60, de 61 a 90, de 91 a 180, de 181 a 360 e mais de 360.
  DEFAULT_BRACKETS = [
    { from: 1, to: 30 }, { from: 31, to: 60 }, { from: 61, to: 90 }, { from: 91, to: 180 }, { from: 181, to: 360 }, { from: 361, to: nil }
  ].freeze
end
