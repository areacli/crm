# O credor: empresa que cobra os próprios clientes. É o tenant do sistema.
class Tenant < ApplicationRecord
  has_one :setting, class_name: "TenantSetting", dependent: :destroy
  has_many :profiles, dependent: :destroy
  has_many :memberships, dependent: :destroy

  validates :name, presence: true

  # Cria o credor com a configuração inicial e os perfis Gestor (todas as permissões) e Operador (MT-21).
  def self.provision!(name)
    transaction do
      create!(name: name).tap do |tenant|
        tenant.create_setting!(aging_brackets: TenantSetting::DEFAULT_BRACKETS)
        tenant.profiles.create!(name: "Gestor", permissions: Permission::ALL)
        tenant.profiles.create!(name: "Operador", permissions: Permission::OPERATOR)
      end
    end
  end
end
