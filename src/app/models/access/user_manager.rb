module Access
  # Gestão de usuários pela tela (especificação 02, R36 a R42). A permissão 10 já foi conferida pela política no credor do
  # vínculo; aqui ficam as regras de dados: o perfil é do credor, a R41 e a PD7, o que é da pessoa (R36a) e o registro de cada
  # ação (quem, quando, antes e depois, sem senha, R42). Cada alteração é uma transação por credor (`Guard.protect`).
  class UserManager
    def initialize(actor, request: nil)
      @actor = actor
      @request = request
    end

    # R36, R37: cria o usuário já ligado ao credor, com senha temporária que só esta chamada devolve.
    def create(tenant:, email_address:, name:, profile:)
      ensure_profile_belongs!(profile, tenant)
      password = TemporaryPassword.generate

      Guard.protect(tenant.id) do
        user = User.create!(name: name.to_s.strip, email_address: email_address, password: password, temporary_password_until: TemporaryPassword.expires_at)
        Membership.create!(user: user, tenant: tenant, profile: profile)
        log("user_created", user, tenant, profile: profile.name)
        [ user, password ]
      end
    end

    # R36a: liga ao credor quem já existe em outro; vale na hora e a pessoa recebe um aviso dentro do sistema.
    def link(tenant:, user:, profile:)
      ensure_profile_belongs!(profile, tenant)
      raise Refused, I18n.t("access.refused.user_inactive") unless user.active?

      Guard.protect(tenant.id) do
        membership = Membership.find_or_initialize_by(user: user, tenant: tenant)
        raise Refused, I18n.t("access.refused.already_linked") if membership.persisted? && membership.active?

        membership.update!(profile: profile, active: true)
        log("membership_linked", user, tenant, profile: profile.name)
        Notice.create!(user: user, kind: "linked_to_tenant", data: { tenant_name: tenant.name, actor_name: @actor.name, profile_name: profile.name })
        membership
      end
    end

    # R32, R41, PD7: muda o perfil do vínculo.
    def change_profile(membership, profile)
      Guard.refuse_self!(@actor, membership)
      ensure_profile_belongs!(profile, membership.tenant)

      Guard.protect(membership.tenant_id) do
        before = membership.profile.name
        membership.update!(profile: profile)
        log("profile_changed", membership.user, membership.tenant, before: before, after: profile.name)
      end
    end

    # R40, R41: desativa ou reativa o vínculo (o usuário segue nos outros credores).
    def set_active(membership, active)
      Guard.refuse_self!(@actor, membership) unless active

      Guard.protect(membership.tenant_id) do
        membership.update!(active: active)
        log(active ? "membership_reactivated" : "membership_deactivated", membership.user, membership.tenant)
      end
    end

    # R36 (revisão 3), R36a: altera o nome, que é da pessoa; só se ela não atua em outro credor.
    def rename(membership, name)
      ensure_personal!(membership)
      before = membership.user.name

      Guard.protect(membership.tenant_id) do
        membership.user.update!(name: name.to_s.strip)
        log("user_renamed", membership.user, membership.tenant, before: before, after: membership.user.name)
      end
    end

    # R37: redefine a senha, com nova temporária que só esta chamada devolve; a anterior e as sessões abertas deixam de valer.
    def reset_password(membership)
      Guard.refuse_self!(@actor, membership)
      ensure_personal!(membership)
      password = TemporaryPassword.generate

      Guard.protect(membership.tenant_id) do
        user = membership.user
        user.update!(password: password, temporary_password_until: TemporaryPassword.expires_at, failed_attempts: 0, locked_until: nil)
        user.sessions.destroy_all
        log("password_reset", user, membership.tenant)
        password
      end
    end

    private
      def ensure_profile_belongs!(profile, tenant)
        raise Refused, I18n.t("access.refused.profile_other_tenant") unless profile.tenant_id == tenant.id
      end

      def ensure_personal!(membership)
        raise Refused, I18n.t("access.refused.personal_data") unless membership.personal_data_editable?
      end

      def log(event, user, tenant, **details)
        AccessEvent.record(event, request: @request, user: user, tenant: tenant, actor: @actor, details: details.presence)
      end
  end
end
