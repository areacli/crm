# A régua (21, R428 a R437a): uma matriz de ações de um credor, com marco, raias, colunas, prioridade, agenda e vigência. Nasce desligada, com a
# trilha padrão e no fim da lista de prioridade; o marco (e com ele o sujeito) não muda depois de criada. A régua só decide e enfileira: quem
# executa cada ação é o executor do tipo.
class Cadence < ApplicationRecord
  include TenantScoped

  # Só o que está na régua: a raia, a coluna e a ação retiradas ficam para o histórico (`removed_at`).
  has_many :lanes, -> { where(removed_at: nil).order(:position) }, class_name: "CadenceLane", dependent: :destroy, inverse_of: :cadence
  has_many :columns, -> { where(removed_at: nil).order(:offset_days) }, class_name: "CadenceColumn", dependent: :destroy, inverse_of: :cadence
  has_many :actions, through: :lanes
  has_many :rounds, class_name: "CadenceRound", dependent: :destroy

  attr_readonly :milestone, :subject

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validates :purpose, inclusion: { in: %w[collection] }
  validates :milestone, inclusion: { in: Cadences::Catalog::MILESTONES.keys }
  validates :schedule_time, format: { with: /\A([01]\d|2[0-3]):(00|30)\z/ }
  validates :valid_from, presence: true
  validate :schedule_days_valid, :validity_order, :return_hours_valid
  validate :can_enable, if: -> { enabled? && will_save_change_to_enabled? }

  before_validation :derive_subject, on: :create
  before_create :take_last_position
  # Desde quando está ligada (R435): a hora prevista de antes disso não é rodada que faltou.
  before_save { self.enabled_since = Time.current if will_save_change_to_enabled?(to: true) && !will_save_change_to_enabled_since? }
  after_create :create_default_lane

  scope :by_priority, -> { order(:position, :id) }

  def bill_object? = Cadences::Catalog.bill_object?(milestone)
  def default_lane = lanes.find(&:default?)

  # A última coluna com ação, quando nenhuma coluna vazia vem depois dela: quem passou dela recebe a última alcançada para sempre (R430).
  def endless?
    with_action = live_actions.distinct.pluck(:cadence_column_id)
    ordered = columns.to_a
    last_action = ordered.rindex { |column| with_action.include?(column.id) }
    last_action.present? && last_action == ordered.size - 1
  end

  # Inclui uma raia logo antes da trilha padrão, que fica sempre por último (R431). `at`: a posição desejada entre as raias com segmento.
  def add_lane!(segment, at: nil)
    transaction do
      fixed = lanes.reject(&:default?)
      at = at.to_i.clamp(1, fixed.size + 1) if at
      at ||= fixed.size + 1
      fixed.select { |lane| lane.position >= at }.each { |lane| lane.update!(position: lane.position + 1) }
      default_lane.update!(position: fixed.size + 2)
      lanes.create!(segment: segment, position: at)
    end
  end

  # As ações que estão na régua: em raia e coluna que também estão.
  def live_actions
    CadenceAction.where(removed_at: nil).joins(:lane, :column)
                 .where(cadence_lanes: { cadence_id: id, removed_at: nil }, cadence_columns: { removed_at: nil })
  end

  # A vigência cobre o dia (R437).
  def valid_on?(date) = valid_from <= date && (valid_until.nil? || valid_until >= date)

  private
    def derive_subject
      self.subject = Cadences::Catalog.subject_of(milestone) if Cadences::Catalog::MILESTONES.key?(milestone.to_s)
    end

    def take_last_position
      self.position ||= (Cadence.where(tenant_id: tenant_id).maximum(:position) || 0) + 1
    end

    def create_default_lane = lanes.create!(default: true, position: 1)

    def schedule_days_valid
      days = Array(schedule_days)
      errors.add(:schedule_days, :blank) if days.empty?
      errors.add(:schedule_days, :invalid) unless days.all? { |day| day.is_a?(Integer) && day.between?(0, 6) } && days.uniq.size == days.size
    end

    def validity_order
      errors.add(:valid_until, :before_start) if valid_from && valid_until && valid_until < valid_from
    end

    def return_hours_valid
      hours = return_hours || {}
      valid = hours.is_a?(Hash) && hours.all? { |kind, value| Cadences::Catalog::KINDS.include?(kind.to_s) && value.is_a?(Integer) && value.between?(1, 720) }
      errors.add(:return_hours, :invalid) unless valid
    end

    # R430: só liga com pelo menos uma coluna com ação.
    def can_enable
      errors.add(:enabled, :without_actions) unless persisted? && live_actions.exists?
    end
end
