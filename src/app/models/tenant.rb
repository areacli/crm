# O credor: empresa que cobra os próprios clientes. É o tenant do sistema.
class Tenant < ApplicationRecord
  has_one :setting, class_name: "TenantSetting", dependent: :destroy
  has_many :profiles, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :payment_channels, dependent: :destroy
  has_many :contact_results, dependent: :destroy

  validates :name, presence: true

  # Cria o credor com a configuração inicial, os perfis Gestor (todas as permissões) e Operador (MT-21) e a lista inicial de resultados de
  # acionamento (R68).
  def self.provision!(name)
    transaction do
      create!(name: name).tap do |tenant|
        tenant.create_setting!(aging_brackets: TenantSetting::DEFAULT_BRACKETS)
        tenant.profiles.create!(name: "Gestor", permissions: Permission::ALL)
        tenant.profiles.create!(name: "Operador", permissions: Permission::OPERATOR)
        Contacts::InitialResults.create_for(tenant)
      end
    end
  end
end
