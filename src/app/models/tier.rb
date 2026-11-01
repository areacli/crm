# Item do enquadramento financeiro de um credor (13, R265 a R268): um segmento de contratos, numa posição, com as regras que o processo pendura
# nele (encargos da 09, prazo e alçadas da promessa da 10, variáveis, limites e parâmetros de acordo da 11). Vale o primeiro item cujo segmento
# casar com o contrato; "Demais" (`catch_all`, sem segmento) é a trilha padrão, sempre por último, e não se move nem se tira. Item tirado do
# enquadramento fica inativo, porque o histórico, as promessas e os acordos congelados continuam apontando para ele.
class Tier < ApplicationRecord
  include TenantScoped

  KINDS = %w[financial].freeze

  # Regra de encargos do item (09, R160): campo vazio (nil) herda o parâmetro do credor (R207a); forma, taxa legal e honorários são só do item.
  CHARGE_FIELDS = %i[fine_pct interest_kind interest_pct interest_form index_code fees_pct fees_in_contract days_convention fine_base].freeze
  INTEREST_KINDS = %w[none fixed legal].freeze
  INTEREST_FORMS = %w[simple compound].freeze
  INDEX_CODES = %w[none ipca inpc igpm].freeze
  DAYS_CONVENTIONS = %w[calendar thirty].freeze
  FINE_BASES = %w[corrected face].freeze
  CDC_FINE_LIMIT = 2 # CDC, art. 52, § 1º (R161): aviso, sem impedir a gravação

  # Parâmetros do acordo com override (11, R207a): campo vazio herda o do credor. Mudar estes campos não muda título nenhum (os acordos congelam os seus).
  AGREEMENT_PARAM_FIELDS = %i[installment_rate_pct installment_method agreement_days_convention agreement_fine_base].freeze
  INSTALLMENT_METHODS = %w[none price sac].freeze
  # Variáveis de acordo do item (11, R207): teto de desconto por componente em duas colunas (parcelado e à vista) e as demais.
  AGREEMENT_VARIABLE_FIELDS = %i[agreement_max_installments agreement_min_installment_cents agreement_min_down_payment_pct agreement_down_payment_days
                                 agreement_validity_days agreement_tolerance_days agreement_break_days].freeze
  # Tudo o que o item carrega e que se copia de outro item ao incluir (R266, SG15).
  RULE_FIELDS = (CHARGE_FIELDS + AGREEMENT_PARAM_FIELDS + AGREEMENT_VARIABLE_FIELDS + %i[agreement_caps promise_max_days]).freeze

  belongs_to :segment, optional: true
  has_many :contract_tiers, dependent: :restrict_with_error
  has_many :contracts, dependent: :nullify
  has_many :promise_limits, dependent: :delete_all
  has_many :agreement_limits, dependent: :delete_all

  # A alçada de cada perfil nasce no mesmo ato em que o item nasce (10, R190; 11, R209); o item incluído com cópia das regras copia também as
  # alçadas e os limites do item de origem (`Tiers::Applier`).
  after_create { PromiseLimit.create_for_tier(self) }
  after_create { AgreementLimit.create_for_tier(self) }

  before_validation :normalize

  validates :kind, inclusion: { in: KINDS }
  validates :interest_kind, inclusion: { in: INTEREST_KINDS }
  validates :interest_form, inclusion: { in: INTEREST_FORMS }
  validates :index_code, inclusion: { in: INDEX_CODES }, allow_nil: true
  validates :days_convention, inclusion: { in: DAYS_CONVENTIONS }, allow_nil: true
  validates :fine_base, inclusion: { in: FINE_BASES }, allow_nil: true
  validates :promise_max_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }
  validates :installment_method, inclusion: { in: INSTALLMENT_METHODS }, allow_nil: true
  validates :agreement_days_convention, inclusion: { in: DAYS_CONVENTIONS }, allow_nil: true
  validates :agreement_fine_base, inclusion: { in: FINE_BASES }, allow_nil: true
  validates :installment_rate_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :agreement_max_installments, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }
  validates :agreement_min_installment_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :agreement_min_down_payment_pct, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }
  validates :agreement_down_payment_days, :agreement_validity_days, :agreement_break_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }
  validates :agreement_tolerance_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 60 }
  validates :fine_pct, :interest_pct, :fees_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :agreement_caps_valid, :fees_need_contract_mark, :segment_fits

  scope :financial, -> { where(kind: "financial") }
  scope :ordered, -> { order(:catch_all, :position, :id) }
  scope :active_ones, -> { where(active: true) }

  def self.catch_all_of(tenant) = find_by!(tenant_id: tenant.id, kind: "financial", catch_all: true)

  # O "Demais" nasce com o credor (R270): sem segmento, regras zeradas.
  def self.create_catch_all!(tenant) = create!(tenant: tenant, kind: "financial", catch_all: true, position: 0)

  # O nome do item é o do segmento que o abre; o da trilha padrão, "Demais".
  def name = catch_all? ? I18n.t("tiers.catch_all") : segment&.name.to_s

  def rules = RULE_FIELDS.index_with { |field| self[field] }

  # Multa acima de 2% num item cujo segmento pode pegar pessoa física leva o aviso do CDC (R161). Com a linguagem, o tipo do público não é um
  # campo fixo: o aviso só sai quando o segmento exige PJ de forma explícita ("tipo = PJ").
  def fine_above_cdc_limit?(fine = fine_pct) = fine.to_d > CDC_FINE_LIMIT && !company_only?

  def company_only?
    return false unless segment

    # Só as condições de fora dos grupos "qualquer:" obrigam todo contrato do item: `tipo = PJ` dentro de um grupo ainda deixa entrar pessoa física (R161).
    segment.expression_object.conditions.any? { |node| node["path"] == "person_type" && !node["negate"] && node["op"] == "eq" && node["value"] == "company" }
  end

  private
    def normalize
      # R162: com a taxa legal a forma dos juros não se aplica (é sempre simples) e não há taxa fixa.
      self.interest_form = "simple" if interest_kind == "legal"
      self.interest_pct = nil if interest_kind != "fixed"
    end

    # R160, R161: honorários só com a marca "o contrato prevê honorários".
    def fees_need_contract_mark
      errors.add(:fees_pct, :fees_without_contract) if fees_pct.to_d.positive? && !fees_in_contract?
    end

    # Teto de desconto de 0 a 100, em pontos inteiros, por componente e por coluna (R207, R209).
    def agreement_caps_valid
      errors.add(:agreement_caps, :invalid) unless Agreements::Caps.valid?(agreement_caps)
    end

    # R265: o enquadramento financeiro só aceita segmentos de contratos; a trilha padrão não tem segmento.
    def segment_fits
      errors.add(:segment, :required) if !catch_all? && segment.nil?
      errors.add(:segment, :subject) if segment && segment.subject != "contracts"
      errors.add(:segment, :other_tenant) if segment && segment.tenant_id != tenant_id
    end
end
