# Usuário: global, identificado pelo e-mail (MT-4). O que ele pode fazer depende do vínculo e do perfil em cada credor.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :tenants, through: :memberships
  has_many :notices, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Só entra quem está ativo e tem vínculo ativo com algum credor ativo (R30).
  def can_sign_in?
    active? && memberships.active.joins(:tenant).merge(Tenant.where(active: true)).exists?
  end

  def locked? = locked_until.present? && locked_until.future?

  # Credores em que o usuário tem a permissão (vínculo e credor ativos), guardados por instância.
  def tenant_ids_with(permission)
    @tenant_ids_with ||= {}
    @tenant_ids_with[permission.to_s] ||= memberships.active.joins(:profile, :tenant).merge(Tenant.where(active: true))
      .where("profiles.permissions @> ?", [ permission.to_s ].to_json).pluck(:tenant_id)
  end

  # A permissão é conferida no credor do registro (MT-3).
  def permitted?(permission, tenant)
    tenant_ids_with(permission).include?(tenant.respond_to?(:id) ? tenant.id : tenant)
  end

  def permitted_anywhere?(permission) = tenant_ids_with(permission).any?
end
