# O credor: empresa que cobra os próprios clientes. É o tenant do sistema. O cadastro dele (CNPJ, razão social, endereço, contatos) é a
# especificação 06 (R106) e só é validado no contexto `:registry`, quando alguém o edita.
class Tenant < ApplicationRecord
  has_one :setting, class_name: "TenantSetting", dependent: :destroy
  has_many :profiles, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :payment_accounts, dependent: :destroy
  has_many :payment_channels, dependent: :destroy
  has_many :contact_results, dependent: :destroy
  has_many :segments, dependent: :destroy

  REGISTRY_FIELDS = %i[cnpj legal_name trade_name street number complement district city state zip email phone].freeze
  ADDRESS_FIELDS = %i[street number complement district city state zip].freeze

  validates :name, presence: true
  validates :legal_name, presence: true, length: { maximum: 300 }, on: :registry
  validates :trade_name, length: { maximum: 300 }, on: :registry
  validate :registry_formats, on: :registry

  before_validation :normalize_registry
  before_save :compute_contact_keys

  # Cria o credor com a configuração inicial, os perfis Gestor (todas as permissões) e Operador (MT-21) e a lista inicial de resultados de
  # acionamento (R68). Com CNPJ, o cadastro (R106) é validado: CNPJ inválido ou já usado por outro credor recusa a criação.
  def self.provision!(name, cnpj: nil, legal_name: nil)
    transaction do
      new(name: name, cnpj: cnpj.presence, legal_name: legal_name.presence).tap do |tenant|
        tenant.save!(context: (tenant.cnpj ? :registry : nil))
        tenant.create_setting!(aging_brackets: TenantSetting::DEFAULT_BRACKETS)
        tenant.profiles.create!(name: "Gestor", permissions: Permission::ALL)
        tenant.profiles.create!(name: "Operador", permissions: Permission::OPERATOR)
        Contacts::InitialResults.create_for(tenant)
        Segment.create_catch_all!(tenant)
      end
    end
  end

  # Nome do credor nas telas que falam em nome dele (R107): o fantasia, ou a razão social se não houver.
  def display_name = trade_name.presence || legal_name.presence || name

  private
    # Cadastro como o banco guarda: CNPJ sem máscara, textos sem espaços nas pontas, UF em maiúsculas, CEP só com dígitos, número vazio "s/n".
    def normalize_registry
      self.cnpj = Document.normalize(cnpj).presence if cnpj_changed?
      (REGISTRY_FIELDS - %i[cnpj]).each { |field| self[field] = self[field].to_s.squish.presence if has_attribute?(field) && !self[field].nil? }
      self.state = state.upcase if state.present?
      self.zip = zip.gsub(/\D/, "") if zip.present? && zip.match?(/\A\d{5}-?\d{3}\z/)
      self.number = "s/n" if number.blank? && ADDRESS_FIELDS.any? { |field| self[field].present? && field != :number }
    end

    def registry_formats
      errors.add(:base, "CNPJ inválido") if cnpj.present? && (cnpj.length != 14 || Document.problem(cnpj))
      errors.add(:base, "já existe um credor com este CNPJ") if cnpj.present? && Tenant.where(cnpj: cnpj).where.not(id: id).exists?
      errors.add(:base, "E-mail inválido: formato inválido") if email.present? && !Registry::Normalizer.email(email).is_a?(Registry::ParsedContact)
      phone_problem = phone.present? ? Registry::Normalizer.phone(phone) : nil
      errors.add(:base, "Telefone inválido: #{phone_problem}") if phone_problem.is_a?(String)
      address_problem = Registry::Normalizer.address(address_hash)
      errors.add(:base, "Endereço inválido: #{address_problem}") if address_problem.is_a?(String)
    end

    def address_hash = ADDRESS_FIELDS.index_with { |field| field == :number && number == "s/n" ? "" : self[field] }

    # R126: a forma normalizada do telefone e do e-mail do credor, para comparar com os contatos dos clientes.
    def compute_contact_keys
      self.phone_key = phone.present? ? Registry::Normalizer.key_for("phone", phone) : nil
      self.email_key = email.present? ? Registry::Normalizer.key_for("email", email) : nil
    end
end
