module Access
  # Perfis por credor (R30 a R35, R41, PD6, PD7, AC7). A permissão 11 já foi conferida pela política no credor do perfil. PD6 e AC7
  # (dependências entre permissões) são validações do próprio `Profile`. Cada alteração é uma transação por credor (`Guard.protect`).
  class ProfileManager
    def initialize(actor, request: nil)
      @actor = actor
      @request = request
    end

    # Devolve o perfil; se for inválido (nome repetido, PD6, AC7), ele volta sem gravar e com os erros.
    def create(tenant:, name:, permissions:)
      profile = tenant.profiles.new(name: name.to_s.strip, permissions: normalize(permissions))
      return profile unless profile.valid?

      Guard.protect(tenant.id) do
        profile.save!
        log("profile_created", tenant, profile: profile.name, after: profile.permissions)
      end
      profile
    end

    # Devolve o perfil; mudar as permissões do próprio perfil é proibido (PD7), e a R41 vale depois da mudança.
    def update(profile, name:, permissions:)
      permissions = normalize(permissions)
      Guard.refuse_own_profile_change!(@actor, profile) if permissions != profile.permissions
      before = { name: profile.name, permissions: profile.permissions }
      profile.assign_attributes(name: name.to_s.strip, permissions: permissions)
      return profile unless profile.valid?

      Guard.protect(profile.tenant_id) do
        profile.save!
        log("profile_updated", profile.tenant, profile: profile.name, before: before, after: { name: profile.name, permissions: profile.permissions })
      end
      profile
    end

    # R35: perfil com usuários não se apaga.
    def destroy(profile)
      count = profile.memberships.count
      raise Refused, I18n.t("access.refused.profile_in_use", count: count) if count.positive?

      Guard.protect(profile.tenant_id) do
        profile.destroy!
        log("profile_deleted", profile.tenant, profile: profile.name)
      end
    end

    private
      # Só valores sem repetição, na ordem da matriz; o que não é permissão conhecida segue para a validação do perfil recusar.
      def normalize(permissions)
        Array(permissions).map(&:to_s).compact_blank.uniq.sort_by { |key| [ Permission::ALL.index(key) || Permission::ALL.size, key ] }
      end

      def log(event, tenant, **details)
        AccessEvent.record(event, request: @request, tenant: tenant, actor: @actor, details: details)
      end
  end
end
