# Lote de distribuição (14, R316): os clientes do filtro da lista, os clientes ou contratos de um segmento, ou os de uma planilha; conferido em
# segundo plano antes de valer, como as importações (decisão 0021), e confirmado de uma vez. É uma fotografia: quem entra no segmento depois não
# é distribuído sozinho.
class DistributionBatch < ApplicationRecord
  include TenantScoped
  belongs_to :operation
  belongs_to :user
  belongs_to :segment, optional: true

  KINDS = %w[selection segment file].freeze
  MAX = 50_000

  enum :status, { checking: "checking", checked: "checked", confirmed: "confirmed", discarded: "discarded", failed: "failed" }, validate: true

  validates :kind, inclusion: { in: KINDS }
  validates :target, inclusion: { in: %w[customer contract] }
  validates :exposure, inclusion: { in: Distribution::EXPOSURES }

  # A conferência vale por 30 minutos (R316).
  def expired? = checked? && checked_at < 30.minutes.ago
end
