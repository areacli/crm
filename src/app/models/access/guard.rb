module Access
  # Proteções das alterações de acesso, sempre por credor (R41, PD7). Cada alteração roda em `Guard.protect`, que serializa as
  # alterações do mesmo credor (trava a linha dele) e confere a R41 depois de aplicada, ainda dentro da transação.
  module Guard
    MANAGER_PERMISSIONS = %w[manage_users manage_profiles].freeze

    # Executa a alteração numa transação, com o credor travado; recusa e desfaz se ninguém ativo ficar com as permissões 10 e 11.
    def self.protect(tenant_id)
      ApplicationRecord.transaction do
        Tenant.lock.find(tenant_id)
        yield.tap { ensure_manager_remains!(tenant_id) }
      end
    end

    # R41: o credor precisa de ao menos um vínculo ativo, de usuário ativo, com "gerenciar usuários" e "gerenciar perfis" juntas.
    def self.ensure_manager_remains!(tenant_id)
      remains = Membership.active.where(tenant_id: tenant_id).joins(:user, :profile).where(users: { active: true })
        .where("profiles.permissions @> ?", MANAGER_PERMISSIONS.to_json).exists?
      raise Refused, I18n.t("access.refused.manager_must_remain") unless remains
    end

    # PD7: ninguém muda o próprio vínculo, nem desativa a própria conta, nem redefine a própria senha por aqui.
    def self.refuse_self!(actor, membership)
      raise Refused, I18n.t("access.refused.self_membership") if membership.user_id == actor.id
    end

    # PD7: ninguém muda as permissões do perfil que ele próprio tem no credor.
    def self.refuse_own_profile_change!(actor, profile)
      own = Membership.where(user_id: actor.id, tenant_id: profile.tenant_id, profile_id: profile.id).exists?
      raise Refused, I18n.t("access.refused.own_profile") if own
    end
  end
end
