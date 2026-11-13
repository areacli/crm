# Sistema de um credor (17, R396 a R399): de onde vêm contratos, títulos e pagamentos. Todo credor nasce com dois: o CRM, pai do que o próprio CRM
# cria (títulos de acordo, uso de crédito, instrumento pago), e o Planilha, de chave natural, que recebe as cargas enquanto o credor não cadastra
# outro. Os demais são os sistemas remotos do credor, cada um com o seu tipo de chave: id próprio (o sistema manda o id do título, do contrato e do
# cliente) ou chave natural (documento e número, código do contrato).
class SourceSystem < ApplicationRecord
  include TenantScoped

  CRM_NAME = "CRM".freeze
  DEFAULT_NAME = "Planilha".freeze

  has_many :imports, dependent: :restrict_with_error
  has_many :customer_identities, dependent: :restrict_with_error

  enum :role, { crm: "crm", default: "default", remote: "remote" }, prefix: true, validate: true
  enum :key_kind, { own_id: "own_id", natural: "natural" }, prefix: :key, validate: true
  enum :status, { active: "active", paused: "paused" }, validate: true

  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id, case_sensitive: false }
  validate :crm_is_fixed, on: :update
  validate :default_keeps_natural_key
  validate :key_kind_is_fixed_after_first_import, on: :update
  validate :role_is_fixed, on: :update

  # Antes das recusas das associações, para a mensagem ser a da regra (R396, R399).
  before_destroy :refuse_destroy, prepend: true

  # Os que recebem importação (R396): todos, menos o CRM.
  scope :receiving, -> { where.not(role: "crm") }

  def self.crm_of(tenant_id) = find_by!(tenant_id: tenant_id, role: "crm")
  def self.default_of(tenant_id) = find_by!(tenant_id: tenant_id, role: "default")

  # Os nomes dos sistemas do credor, por id, quando há mais de um além do CRM; com um só, nil. É quando as telas passam a dizer de que sistema é cada
  # coisa (R422, R423): com um só, nada muda.
  def self.names_if_several(tenant_id)
    systems = where(tenant_id: tenant_id).pluck(:id, :name, :role)
    systems.to_h { |id, name, _| [ id, name ] } if systems.count { |_, _, role| role != "crm" } > 1
  end

  # Os dois sistemas com que todo credor nasce (R396).
  def self.create_defaults!(tenant)
    [ create!(tenant: tenant, name: CRM_NAME, role: "crm", key_kind: "natural"), create!(tenant: tenant, name: DEFAULT_NAME, role: "default", key_kind: "natural") ]
  end

  # R397 e R399: depois da primeira importação o tipo de chave não muda e o sistema não é mais excluído.
  def imported? = imports.exists?

  private
    def crm_is_fixed
      errors.add(:base, "o sistema CRM não pode ser alterado") if role_crm? && changed?
    end

    def default_keeps_natural_key
      errors.add(:key_kind, "do sistema #{name} é sempre chave natural") if !role_remote? && !key_natural?
    end

    def key_kind_is_fixed_after_first_import
      errors.add(:key_kind, "não muda depois da primeira importação") if key_kind_changed? && imported?
    end

    def role_is_fixed
      errors.add(:role, "não muda") if role_changed?
    end

    def refuse_destroy
      reason = if !role_remote? then "o sistema #{name} não pode ser excluído"
      elsif imported? then "sistema com importação não pode ser excluído, só pausado"
      elsif TenantSetting.exists?(customer_record_system_id: id) then "o sistema #{name} é o definido em Cadastro entre sistemas; troque a política antes de excluir"
      end
      return unless reason

      errors.add(:base, reason)
      throw :abort
    end
end
