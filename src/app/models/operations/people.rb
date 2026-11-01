module Operations
  # Pessoas da operação (14, R310, R310a): o gestor da operação cadastra e desativa as pessoas dela, uma vez para todos os credores. Desativar
  # uma pessoa encerra os vínculos dela em todos os credores (registrado em cada um). A operação nunca fica sem gestor ativo.
  class People
    def initialize(actor) = @actor = actor

    # Pessoa nova com senha temporária (02, R37), ou a pessoa que já existe no sistema e ainda não é de operação nem de equipe de credor
    # (OPD14). Devolve [usuário, senha temporária ou nil].
    def create_person(operation, name:, email_address:, manager: false)
      email = email_address.to_s.strip.downcase
      user = User.find_by(email_address: email)
      password = nil
      if user
        raise Accreditor::Refused, I18n.t("operations.refused.person_taken") if user.operation_member || user.memberships.where(operation_id: nil).exists?
      else
        password = Access::TemporaryPassword.generate
        user = User.create!(name: name.to_s.strip, email_address: email, password: password, temporary_password_until: Access::TemporaryPassword.expires_at)
      end
      OperationMember.create!(operation: operation, user: user, manager: manager)
      [ user, password ]
    end

    def set_active(member, active)
      raise Accreditor::Refused, I18n.t("operations.refused.self") if member.user_id == @actor.id && !active
      raise Accreditor::Refused, I18n.t("operations.refused.last_manager") if !active && member.manager? && member.operation.managers.where.not(id: member.id).none?

      ApplicationRecord.transaction do
        member.update!(active: active)
        next if active

        member.user.memberships.active.where(operation_id: member.operation_id).find_each do |membership|
          membership.update!(active: false)
          Change.record!(membership, "operation_unlinked", tenant_id: membership.tenant_id, actor: @actor, origin: "screen", before: member.user.name, note: "pessoa desativada na operação")
        end
      end
    end

    def set_manager(member, manager)
      raise Accreditor::Refused, I18n.t("operations.refused.last_manager") if !manager && member.operation.managers.where.not(id: member.id).none?

      member.update!(manager: manager)
    end
  end
end
