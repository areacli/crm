module Operations
  # Credenciamento e vínculos de operação do lado do credor (14, R306, R307, R310). A permissão (18, ou 10 para vínculos) já foi conferida pela
  # política no credor. Cada ação fica no histórico do credor, com quem, quando, antes e depois.
  class Accreditor
    Refused = Class.new(StandardError)

    def initialize(actor) = @actor = actor

    # R306: pelo CNPJ. A operação que já existe é só credenciada (o credor vê dela razão social, nome curto e CNPJ); a nova nasce com o primeiro
    # gestor da operação, com senha temporária, que só esta chamada devolve. Devolve [credenciamento, usuário criado ou nil, senha ou nil].
    def accredit(tenant:, cnpj:, legal_name: nil, short_name: nil, manager_name: nil, manager_email: nil)
      ApplicationRecord.transaction do
        operation = Operation.find_by(cnpj: Document.normalize(cnpj))
        created_user = password = nil
        unless operation
          operation = Operation.create!(cnpj: cnpj, legal_name: legal_name, short_name: short_name)
          created_user, password = People.new(@actor).create_person(operation, name: manager_name, email_address: manager_email, manager: true)
        end
        raise Refused, I18n.t("operations.refused.already_accredited", name: operation.short_name) if Accreditation.exists?(tenant: tenant, operation: operation)

        accreditation = Accreditation.create!(tenant: tenant, operation: operation)
        log(accreditation, "accredited", after: operation.short_name)
        [ accreditation, created_user, password ]
      end
    end

    # R307: suspender, encerrar e reativar pedem motivo. Encerrar encerra as distribuições deste credor (R311, R317).
    def change_status(accreditation, status, reason)
      raise Refused, I18n.t("operations.refused.reason_required") if reason.to_s.strip.blank?

      ApplicationRecord.transaction do
        before = accreditation.status
        accreditation.update!(status: status, status_reason: reason.to_s.strip.first(300))
        Distributions::Closer.new(@actor).close_all(accreditation, reason: "accreditation_ended") if accreditation.ended?
        log(accreditation, "status_changed", field: "status", before: before, after: status, note: reason.to_s.strip.first(300))
      end
      ReachBuilder.new(accreditation.tenant).rebuild
    end

    # R310: o vínculo da pessoa da operação neste credor, com um perfil disponível para operações. Reativa o vínculo desativado.
    def link(accreditation, user:, profile:)
      member = OperationMember.find_by(user: user, operation: accreditation.operation, active: true)
      raise Refused, I18n.t("operations.refused.not_member") unless member
      raise Refused, I18n.t("operations.refused.profile_not_available") unless profile.tenant_id == accreditation.tenant_id && profile.available_to_operations?

      membership = Membership.find_or_initialize_by(user: user, tenant: accreditation.tenant)
      raise Refused, I18n.t("operations.refused.team_member") if membership.persisted? && membership.operation_id.nil?

      membership.update!(profile: profile, operation: accreditation.operation, active: true)
      log(membership, "operation_linked", after: "#{user.name} · #{profile.name}")
      Notice.create!(user: user, kind: "linked_to_tenant", data: { tenant_name: accreditation.tenant.name, actor_name: @actor.name, profile_name: profile.name })
      membership
    end

    def unlink(membership)
      membership.update!(active: false)
      log(membership, "operation_unlinked", before: membership.user.name)
    end

    private
      def log(subject, event, **fields) = Change.record!(subject, event, tenant_id: subject.tenant_id, actor: @actor, origin: "screen", **fields)
  end
end
