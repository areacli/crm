# Conta de pagamento do credor (12, R260): o vínculo com um fornecedor de boleto, Pix ou cartão, por modalidade e ambiente, ligado a um canal
# de recebimento. Os campos vêm do manifesto do fornecedor. Os comuns ficam em `config`; os secretos e os arquivos (certificado .p12), em
# `secrets`, cifrado pelo Active Record Encryption (R262) e nunca devolvido (R261). De cada certificado só se guarda titular, validade e
# impressão digital, em `file_details`.
class PaymentAccount < ApplicationRecord
  include TenantScoped

  belongs_to :channel, class_name: "PaymentChannel", inverse_of: :payment_accounts
  has_many :instruments, class_name: "PaymentInstrument", foreign_key: :account_id, inverse_of: :account, dependent: :restrict_with_error
  has_many :events, class_name: "PaymentEvent", foreign_key: :account_id, inverse_of: :account, dependent: :destroy

  enum :modality, { boleto: "boleto", pix: "pix", card: "card" }, validate: true
  enum :environment, { sandbox: "sandbox", production: "production" }, validate: true

  attribute :secrets, :json, default: -> { {} }
  encrypts :secrets

  normalizes :nickname, with: ->(value) { value.to_s.strip }

  validates :nickname, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validate :provider_supports_modality
  validate :channel_of_same_tenant
  validate :only_one_active
  validate :fields_valid
  validate :pending_files_valid

  scope :active, -> { where(active: true) }

  # Dias antes do vencimento do certificado em que o aviso nasce (R264).
  WARNING_DAYS = 30
  # O segredo anterior do webhook continua valendo por 24 horas depois da troca (R265).
  WEBHOOK_OVERLAP = 24.hours

  # Nomes dos campos cujo valor foi trocado nesta gravação (para o histórico, que não leva o valor).
  def replaced_secrets = (@replaced_secrets ||= [])
  def replaced_files = (@replaced_files ||= [])

  def adapter = Payments::Providers.adapter(provider)
  def manifest = Payments::Providers.manifest(provider)
  def provider_available? = Payments::Providers.known?(provider)
  def fields = provider_available? && modality.present? ? manifest.fields_for(modality) : []

  # R269: a conta que emitiu instrumento só se desativa.
  def used? = instruments.exists?

  def secret_set?(name) = secrets[name.to_s].present?

  def file_info(name) = file_details[name.to_s]

  # Aplica o que veio do formulário. `values`: config (campos comuns), secrets (campos secretos; vazio mantém) e files (arquivos enviados).
  def assign_values(config: {}, secrets: {}, files: {})
    fields.each do |field|
      if field.generated
        next
      elsif field.file?
        upload = files[field.name]
        pending_files[field.name] = upload.read if upload.respond_to?(:read)
        # A senha do arquivo novo vale como veio no formulário (vazio = sem senha), nunca a do arquivo anterior.
        replace_secret(field.password_field, secrets[field.password_field].to_s, even_blank: true) if pending_files.key?(field.name) && field.password_field
      elsif field.secret?
        replace_secret(field.name, secrets[field.name]) unless pending_files.any? { |name, _| manifest.field(name).password_field == field.name }
      elsif config.key?(field.name)
        self.config = self.config.merge(field.name => cast(field, config[field.name])).compact
      end
    end
    self.config = defaults_for_missing_fields.merge(self.config) if new_record?
  end

  # Segredos do nosso webhook que valem agora: o atual e, por 24 horas depois da troca, o anterior (R265).
  def webhook_secrets(now: Time.current)
    [ secrets["webhook_secret"], (secrets["webhook_secret_previous"] if webhook_previous_until && webhook_previous_until > now) ].compact_blank
  end

  # Troca (ou gera) o segredo do webhook e devolve o novo em claro, uma única vez.
  def rotate_webhook_secret!(now: Time.current)
    current = secrets["webhook_secret"]
    new_secret = SecureRandom.base58(40)
    update!(secrets: secrets.merge("webhook_secret" => new_secret, "webhook_secret_previous" => current).compact, webhook_previous_until: (now + WEBHOOK_OVERLAP if current))
    new_secret
  end

  # Menor validade entre os certificados da conta, ou nil.
  def certificate_expires_on
    file_details.values.filter_map { |info| Date.iso8601(info["not_after"]) if info["not_after"] }.min
  end

  before_save :store_pending_files

  private
    def pending_files = (@pending_files ||= {})

    def replace_secret(name, value, even_blank: false)
      return if value.blank? && !even_blank

      if value.blank?
        self.secrets = secrets.except(name)
      else
        self.secrets = secrets.merge(name => value.to_s)
        replaced_secrets << name
      end
    end

    # Número vazio apaga o campo; texto sem número fica como veio para a validação recusar.
    def cast(field, value)
      value = value.to_s.strip
      return nil if value.blank?
      return value unless field.numeric?

      number = BigDecimal(value.tr(",", "."), exception: false)
      number ? (number.frac.zero? ? number.to_i : number.to_f) : value
    end

    def defaults_for_missing_fields
      fields.reject { |field| field.default.nil? || field.secret? }.to_h { |field| [ field.name, field.default ] }
    end

    def provider_supports_modality
      if !provider_available? then errors.add(:provider, :unavailable)
      elsif modality.present? && !manifest.supports?(modality) then errors.add(:modality, :unsupported)
      end
    end

    def channel_of_same_tenant
      errors.add(:channel, :other_tenant) if channel && tenant_id != channel.tenant_id
    end

    def only_one_active
      return unless active? && modality.present? && environment.present?
      return unless PaymentAccount.active.where(tenant_id: tenant_id, modality: modality, environment: environment).where.not(id: id).exists?

      errors.add(:base, :active_exists, modality: I18n.t("payments.accounts.modalities.#{modality}"), environment: I18n.t("payments.accounts.environments.#{environment}"))
    end

    def fields_valid
      fields.each do |field|
        label = manifest.label_of(field)
        next if field.generated

        if field.file?
          errors.add(:base, :required_field, field: label) if field.required && !file_details.key?(field.name) && !pending_files.key?(field.name)
        elsif field.secret?
          errors.add(:base, :required_field, field: label) if field.required && !secret_set?(field.name)
        else
          value = config[field.name]
          if value.blank? then errors.add(:base, :required_field, field: label) if field.required
          elsif field.numeric? then validate_number(field, label, value)
          elsif field.type == "select" then errors.add(:base, :invalid_option, field: label) unless field.options.include?(value.to_s)
          elsif value.to_s.length > field.maxlength then errors.add(:base, :too_long_field, field: label, count: field.maxlength)
          end
        end
      end
    end

    def validate_number(field, label, value)
      if !value.is_a?(Numeric) then errors.add(:base, :not_a_number, field: label)
      elsif (field.min && value < field.min) || (field.max && value > field.max) then errors.add(:base, :out_of_range, field: label, min: field.min, max: field.max)
      end
    end

    # Abre cada certificado enviado (só em memória); o que não presta recusa a gravação (R263).
    def pending_files_valid
      @certificates = {}
      pending_files.each do |name, bytes|
        field = manifest.field(name)
        if field&.certificate?
          @certificates[name] = Payments::Certificate.read(bytes, secrets[field.password_field])
        end
      rescue Payments::Certificate::Invalid => error
        errors.add(:base, "#{manifest.label_of(field)}: #{error.message}")
      end
    end

    # Cifra o arquivo (Base64 dentro de `secrets`) e guarda só os dados públicos do certificado; zera o aviso de vencimento (R264).
    def store_pending_files
      return if pending_files.empty?

      pending_files.each do |name, bytes|
        self.secrets = secrets.merge(name => Base64.strict_encode64(bytes))
        self.file_details = file_details.merge(name => @certificates.fetch(name).to_h) if @certificates&.key?(name)
        replaced_files << name
      end
      self.certificate_warned_for = nil
      @pending_files = {}
    end
end
