# Segmento (13, R252): filtro nomeado de um credor. Descreve um público de clientes ou de contratos na linguagem dos segmentos e, sozinho, não
# muda nada: só tem efeito quando um processo o consome (o enquadramento financeiro, `Tier`; o filtro da lista de clientes). O sujeito não muda
# depois de criado. Em uso, não se apaga: só se desativa (R273).
class Segment < ApplicationRecord
  include TenantScoped

  SUBJECTS = Segments::Catalog::SUBJECTS

  has_many :tiers, dependent: :restrict_with_error

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 100 }
  validates :subject, inclusion: { in: SUBJECTS }
  validate :unique_name, :expression_valid, :subject_unchanged

  scope :ordered, -> { order(:name_key, :id) }
  scope :active_ones, -> { where(active: true) }

  def expression_object = Segments::Expression.new(expression)

  def text(result_names: nil) = Segments::Text.new(expression_object, result_names: result_names)

  # Onde o segmento é usado: os itens ativos de enquadramento (R273, R295).
  def uses = tiers.where(active: true).order(:kind, :position)

  def used? = uses.exists?

  private
    def normalize
      self.name = name.to_s.squish
      self.name_key = FoldedText.fold(name)
      self.expression = (expression || {}).deep_stringify_keys.merge("grammar" => Segments::Expression::GRAMMAR, "subject" => subject)
    end

    def unique_name
      return if name_key.blank?

      errors.add(:name, :taken) if Segment.where(tenant_id: tenant_id, name_key: name_key).where.not(id: id).exists?
    end

    def expression_valid
      tree = expression_object
      return if tree.valid?

      tree.errors.each { |where, messages| messages.each { |message| errors.add(:expression, "#{where == 'base' ? '' : "#{I18n.t('segments.condition', number: where.split('.').map { |part| part.to_i + 1 }.join('.'))}: "}#{message}") } }
    end

    def subject_unchanged
      errors.add(:subject, :unchangeable) if persisted? && subject_changed?
    end
end
