module Access
  # Comando do administrador no servidor (R43, `bin/rails crm:user`): última saída para criar, ligar, renomear, desativar, reativar e
  # redefinir a senha de usuários, fora da interface e fora da R41. Cada ação fica no registro de acessos, sem senha (R42).
  # `run` devolve as linhas da resposta; uma recusa vira `Access::Refused` com a mensagem.
  class AdminCommand
    ACTIONS = %w[ create link rename list deactivate reactivate reset_password ].freeze

    # `options`: name, tenant (nome do credor), profile (nome, padrão Gestor) e password (definitiva; sem ela, gera a temporária).
    def run(action, email_address, options = {})
      raise Refused, "Ação desconhecida. Use #{ACTIONS.join(', ')}." unless ACTIONS.include?(action.to_s)

      options = options.symbolize_keys
      return list if action.to_s == "list"

      email_address = email_address.to_s.strip.downcase
      raise Refused, "Informe o e-mail." if email_address.blank?

      public_send(action, email_address, options)
    end

    def create(email_address, options)
      raise Refused, "Usuário já existe." if User.exists?(email_address: email_address)

      tenant, profile = tenant_and_profile(options)
      password, temporary = password_for(options)
      user = ApplicationRecord.transaction do
        User.create!(name: options[:name].presence || email_address, email_address: email_address, password: password,
                     temporary_password_until: (TemporaryPassword.expires_at if temporary)).tap do |created|
          Membership.create!(user: created, tenant: tenant, profile: profile)
          log("admin_user_created", created, tenant, profile: profile.name)
        end
      end
      [ "Usuário #{user.email_address} criado no credor #{tenant.name} com o perfil #{profile.name}.", *announce(password, temporary) ]
    rescue ActiveRecord::RecordInvalid => error
      raise Refused, error.record.errors.full_messages.to_sentence
    end

    def link(email_address, options)
      user = find_user(email_address)
      tenant, profile = tenant_and_profile(options)
      Membership.find_or_initialize_by(user: user, tenant: tenant).update!(profile: profile, active: true)
      log("admin_membership_linked", user, tenant, profile: profile.name)
      [ "Usuário #{email_address} ligado ao credor #{tenant.name} com o perfil #{profile.name}." ]
    end

    def rename(email_address, options)
      user = find_user(email_address)
      raise Refused, "Informe o novo nome em NAME." if options[:name].blank?

      before = user.name
      user.update!(name: options[:name].strip)
      log("admin_user_renamed", user, nil, before: before, after: user.name)
      [ "Nome alterado." ]
    rescue ActiveRecord::RecordInvalid => error
      raise Refused, error.record.errors.full_messages.to_sentence
    end

    def deactivate(email_address, _options)
      user = find_user(email_address)
      user.update!(active: false)
      user.sessions.destroy_all
      log("admin_user_deactivated", user, nil)
      [ "Usuário desativado em todos os credores; as sessões abertas dele foram encerradas." ]
    end

    def reactivate(email_address, _options)
      user = find_user(email_address)
      user.update!(active: true)
      log("admin_user_reactivated", user, nil)
      [ "Usuário reativado." ]
    end

    def reset_password(email_address, options)
      user = find_user(email_address)
      password, temporary = password_for(options)
      user.update!(password: password, temporary_password_until: (TemporaryPassword.expires_at if temporary), failed_attempts: 0, locked_until: nil)
      user.sessions.destroy_all
      log("admin_password_reset", user, nil)
      [ "Senha redefinida.", *announce(password, temporary) ]
    rescue ActiveRecord::RecordInvalid => error
      raise Refused, error.record.errors.full_messages.to_sentence
    end

    private
      def list
        rows = Membership.includes(:user, :tenant, :profile).joins(:user).order("users.email_address", :tenant_id).map do |membership|
          situation = membership.user.active? && membership.active? ? "ativo" : "inativo"
          [ membership.user.email_address, membership.user.name, membership.tenant.name, membership.profile.name, situation ].join(" | ")
        end
        [ "E-mail | Nome | Credor | Perfil | Situação", *rows ]
      end

      def find_user(email_address) = User.find_by(email_address: email_address) || raise(Refused, "Usuário não encontrado.")

      def tenant_and_profile(options)
        tenant = Tenant.find_by(name: options[:tenant]) || raise(Refused, "Informe em TENANT o nome de um credor existente.")
        profile = tenant.profiles.find_by(name: options[:profile].presence || "Gestor") || raise(Refused, "Perfil inexistente nesse credor.")
        [ tenant, profile ]
      end

      # Senha definitiva (sem prazo, validada pela R26 ao gravar) ou, sem ela, a temporária de 72 horas.
      def password_for(options) = options[:password].present? ? [ options[:password], false ] : [ TemporaryPassword.generate, true ]

      def announce(password, temporary) = temporary ? [ "Senha temporária (vale 72 horas; não será mostrada de novo): #{password}" ] : []

      def log(event, user, tenant, **details)
        AccessEvent.record(event, user: user, tenant: tenant, details: details.presence)
      end
  end
end
