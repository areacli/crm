# Usuário: global, identificado pelo e-mail (MT-4). O que ele pode fazer depende do vínculo e do perfil em cada credor.
class User < ApplicationRecord
  has_secure_password
  # Campo virtual do formulário de troca de senha (R39): só carrega o erro "senha atual não confere".
  attr_accessor :current_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :tenants, through: :memberships
  has_many :notices, dependent: :destroy
  # Pessoa de operação (14, R309): pertence a uma operação só.
  has_one :operation_member, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, strong_password: true, allow_nil: true

  MAX_FAILED_ATTEMPTS = 5
  LOCK_FOR = 15.minutes

  # Só entra quem está ativo, com a senha temporária dentro do prazo (R37) e vínculo ativo com algum credor ativo (R30); o gestor da operação
  # entra mesmo sem vínculo, para cuidar das pessoas dela (14, R310a).
  def can_sign_in?
    active? && !temporary_password_expired? && (memberships.usable.joins(:tenant).merge(Tenant.where(active: true)).exists? || operation_manager?)
  end

  def locked? = locked_until.present? && locked_until.future?

  # Enquanto a senha for temporária, só a tela de definir a senha abre (R38).
  def temporary_password? = temporary_password_until.present?

  def temporary_password_expired? = temporary_password_until.present? && temporary_password_until.past?

  # R27: a quinta tentativa errada seguida bloqueia por 15 minutos e zera a contagem. Devolve true quando esta tentativa bloqueou.
  def register_failed_login!
    with_lock do
      self.failed_attempts += 1
      blocked = failed_attempts >= MAX_FAILED_ATTEMPTS
      if blocked
        self.failed_attempts = 0
        self.locked_until = LOCK_FOR.from_now
      end
      save!(validate: false)
      blocked
    end
  end

  def register_successful_login!
    update_columns(failed_attempts: 0, locked_until: nil, last_login_at: Time.current)
  end

  # Troca da própria senha (R38, R39). `current:` é a senha atual, pedida de quem não está com senha temporária (quem acabou de
  # entrar com a temporária não a repete). A nova segue a R26, não pode repetir a anterior e tira o usuário do modo temporário.
  # Devolve false, com os erros no usuário, se algo estiver errado.
  def change_password(new_password, confirmation, current: nil, require_current: true)
    same_as_before = new_password.present? && stored_password?(new_password)
    wrong_current = require_current && !stored_password?(current)
    self.password = new_password
    self.password_confirmation = confirmation
    valid?
    errors.add(:current_password, :invalid) if wrong_current
    errors.add(:password, :blank) if new_password.blank?
    errors.add(:password, :same_as_current) if same_as_before
    return false if errors.any?

    self.temporary_password_until = nil
    save!(validate: false)
  end

  # Credores em que o usuário tem a permissão (vínculo e credor ativos), guardados por instância.
  def tenant_ids_with(permission)
    @tenant_ids_with ||= {}
    @tenant_ids_with[permission.to_s] ||= memberships.usable.joins(:profile, :tenant).merge(Tenant.where(active: true))
      .where("profiles.permissions @> ?", [ permission.to_s ].to_json).pluck(:tenant_id)
  end

  # A permissão é conferida no credor do registro (MT-3).
  def permitted?(permission, tenant)
    tenant_ids_with(permission).include?(tenant.respond_to?(:id) ? tenant.id : tenant)
  end

  def permitted_anywhere?(permission) = tenant_ids_with(permission).any?

  # Operação da pessoa (14, R309) e o gestor dela (R310a).
  def operation = operation_member&.active? ? operation_member.operation : nil
  def operation_manager? = operation_member&.active? && operation_member.manager? && operation_member.operation.active?

  # Credores em que o vínculo é de operação e o credenciamento está suspenso: o aviso ao entrar (R308).
  def suspended_operation_tenants
    Tenant.where(id: memberships.active.where.not(operation_id: nil)
                                .joins("JOIN accreditations a ON a.tenant_id = memberships.tenant_id AND a.operation_id = memberships.operation_id AND a.status = 'suspended'")
                                .select(:tenant_id))
  end

  private
    # Confere contra a senha gravada, e não contra a que o objeto já recebeu em memória.
    def stored_password?(plain) = BCrypt::Password.new(password_digest_in_database).is_password?(plain.to_s)
end
