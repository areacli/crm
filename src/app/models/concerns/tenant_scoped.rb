# Registro de domínio de um credor (MT-1). `visible_to` devolve só o que o usuário pode ver pelas permissões dele em cada credor:
# nada de `default_scope`, o escopo é pedido de forma explícita em cada consulta.
module TenantScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :tenant
  end

  class_methods do
    def visible_to(user, *permissions)
      where(tenant_id: permissions.flat_map { |permission| user.tenant_ids_with(permission) }.uniq)
    end
  end
end
