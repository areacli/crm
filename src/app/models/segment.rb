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

  # Regra de encargos do segmento (09, R160): campo vazio (nil) herda o parâmetro do credor (R207a); forma, taxa legal e honorários são só do segmento.
  CHARGE_FIELDS = %i[fine_pct interest_kind interest_pct interest_form index_code fees_pct fees_in_contract days_convention fine_base].freeze
  INTEREST_KINDS = %w[none fixed legal].freeze
  INTEREST_FORMS = %w[simple compound].freeze
  INDEX_CODES = %w[none ipca inpc igpm].freeze
  DAYS_CONVENTIONS = %w[calendar thirty].freeze
  FINE_BASES = %w[corrected face].freeze
  CDC_FINE_LIMIT = 2 # CDC, art. 52, § 1º (R161): aviso, sem impedir a gravação

  has_many :contract_segments, dependent: :restrict_with_error
  has_many :contracts, dependent: :nullify
  has_many :promise_limits, dependent: :delete_all

  # A alçada de cada perfil nasce no mesmo ato em que o segmento nasce (10, R190).
  after_create { PromiseLimit.create_for_segment(self) }

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 100 }
  validates :person_type, inclusion: { in: PERSON_TYPES }, allow_nil: true
  validates :broke_agreement, inclusion: { in: %w[yes no] }, allow_nil: true
  validates :interest_kind, inclusion: { in: INTEREST_KINDS }
  validates :interest_form, inclusion: { in: INTEREST_FORMS }
  validates :index_code, inclusion: { in: INDEX_CODES }, allow_nil: true
  validates :days_convention, inclusion: { in: DAYS_CONVENTIONS }, allow_nil: true
  validates :fine_base, inclusion: { in: FINE_BASES }, allow_nil: true
  validates :promise_max_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }
  validates :fine_pct, :interest_pct, :fees_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :unique_name, :ranges_consistent, :catch_all_has_no_criteria, :fees_need_contract_mark

  scope :ordered, -> { order(:catch_all, :position, :id) }
  scope :active_ones, -> { where(active: true) }

  def self.catch_all_of(tenant) = find_by!(tenant_id: tenant.id, catch_all: true)

  # O "Demais" nasce com o credor (R148).
  def self.create_catch_all!(tenant) = create!(tenant: tenant, name: "Demais", catch_all: true, position: 0)

  def criteria = CRITERIA.index_with { |name| self[name] }

  def any_criteria? = criteria.values.any?(&:present?)

  # Multa acima de 2% num segmento que aceita pessoa física (tipo "pessoa física" ou "tanto faz") leva o aviso do CDC (R161).
  def fine_above_cdc_limit?(fine = fine_pct) = fine.to_d > CDC_FINE_LIMIT && person_type != "company"

  private
    def normalize
      self.name = name.to_s.squish
      self.name_key = FoldedText.fold(name)
      # R162: com a taxa legal a forma dos juros não se aplica (é sempre simples) e não há taxa fixa.
      self.interest_form = "simple" if interest_kind == "legal"
      self.interest_pct = nil if interest_kind != "fixed"
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

    # R160, R161: honorários só com a marca "o contrato prevê honorários".
    def fees_need_contract_mark
      errors.add(:fees_pct, :fees_without_contract) if fees_pct.to_d.positive? && !fees_in_contract?
    end

    def catch_all_has_no_criteria
      errors.add(:base, :catch_all_criteria) if catch_all? && any_criteria?
    end
end
