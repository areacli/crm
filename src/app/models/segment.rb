# Segmento de contratos de um credor (R148): critérios combinados, em ordem; vale o primeiro que casar (R149). "Demais" (catch_all) é o último,
# não tem critérios e nunca é desativado nem movido. Critério vazio aceita qualquer valor. Detalhes do cálculo: `Segments::Calculator`.
class Segment < ApplicationRecord
  include TenantScoped

  # Critérios numéricos com mínimo e máximo (R150): atraso do contrato, saldo em cobrança sem encargos, títulos vencidos, percentual do valor
  # vencido, clientes no contrato e idade do contrato.
  RANGES = %i[overdue_days balance_cents overdue_bills overdue_percent customers age_days].freeze
  RANGE_COLUMNS = RANGES.flat_map { |name| [ :"min_#{name}", :"max_#{name}" ] }.freeze
  CRITERIA = (RANGE_COLUMNS + %i[person_type broke_agreement products]).freeze
  PERSON_TYPES = %w[person company mixed].freeze

  has_many :contract_segments, dependent: :restrict_with_error
  has_many :contracts, dependent: :nullify

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 100 }
  validates :person_type, inclusion: { in: PERSON_TYPES }, allow_nil: true
  validates :broke_agreement, inclusion: { in: %w[yes no] }, allow_nil: true
  validate :unique_name, :ranges_consistent, :catch_all_has_no_criteria

  scope :ordered, -> { order(:catch_all, :position, :id) }
  scope :active_ones, -> { where(active: true) }

  def self.catch_all_of(tenant) = find_by!(tenant_id: tenant.id, catch_all: true)

  # O "Demais" nasce com o credor (R148).
  def self.create_catch_all!(tenant) = create!(tenant: tenant, name: "Demais", catch_all: true, position: 0)

  def criteria = CRITERIA.index_with { |name| self[name] }

  def any_criteria? = criteria.values.any?(&:present?)

  private
    def normalize
      self.name = name.to_s.squish
      self.name_key = FoldedText.fold(name)
      self.products = Array(products).filter_map { |product| FoldedText.fold(product).presence }.uniq
    end

    def unique_name
      return if name_key.blank?

      errors.add(:name, :taken) if Segment.where(tenant_id: tenant_id, name_key: name_key).where.not(id: id).exists?
    end

    # Mínimo maior que o máximo, em qualquer critério numérico, é recusado com a mensagem do campo (caso de exceção); o percentual vai de 0 a 100.
    def ranges_consistent
      RANGES.each do |range|
        low = self[:"min_#{range}"]
        high = self[:"max_#{range}"]
        errors.add(:"min_#{range}", :negative) if low&.negative?
        errors.add(:"max_#{range}", :negative) if high&.negative?
        errors.add(:"max_#{range}", :range_inverted) if low && high && low > high
      end
      %i[min_overdue_percent max_overdue_percent].each { |name| errors.add(name, :percent) if self[name] && self[name] > 100 }
    end

    def catch_all_has_no_criteria
      errors.add(:base, :catch_all_criteria) if catch_all? && any_criteria?
    end
end
