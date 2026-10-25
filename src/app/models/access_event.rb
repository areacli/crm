# Registro de acesso: entradas, saídas, bloqueios e ações do administrador (R29, R42). Só inserção.
class AccessEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :tenant, optional: true
  belongs_to :actor, class_name: "User", optional: true

  def self.record(event, request: nil, user: nil, email_address: nil, tenant: nil, actor: nil, details: nil)
    create!(event: event, user: user, tenant: tenant, actor: actor, email_address: email_address || user&.email_address,
            ip_address: request&.remote_ip, details: details)
  end
end
