module Agreements
  # Acordos pendentes que o usuário pode aprovar (11, R216, R243): nos credores em que tem "negociar acordos" e consulta a carteira, com os limites atuais do perfil
  # dele no credor cobrindo a proposta, e nunca as que ele mesmo montou. A lista e o número do menu usam a mesma consulta. A comparação do limite é em Ruby
  # sobre as pendentes (poucas por credor); índice: `agreements (tenant_id, state, valid_until)`.
  module Pending
    module_function

    def for(user)
      tenant_ids = user.tenant_ids_with("negotiate_agreements") & user.tenant_ids_with("view_portfolio")
      pending = Agreement.where(tenant_id: tenant_ids, state: "pending").where("agreements.user_id is distinct from ?", user.id).includes(:segment, :tenant).to_a
      return Agreement.none if pending.empty?

      # Os limites do usuário em cada credor, lidos uma vez (a lista e o número do menu pedem esta consulta a cada página).
      profile_by_tenant = Membership.active.where(user_id: user.id, tenant_id: tenant_ids).includes(:profile).to_h { |membership| [ membership.tenant_id, membership.profile ] }
      limits = AgreementLimit.where(profile_id: profile_by_tenant.values.map(&:id), segment_id: pending.map(&:segment_id)).index_by { |limit| [ limit.profile_id, limit.segment_id ] }
      ids = pending.select do |agreement|
        profile = profile_by_tenant[agreement.tenant_id] or next false
        segment = agreement.segment || Segment.catch_all_of(agreement.tenant)
        Limits.covers?(limits[[ profile.id, segment.id ]] || AgreementLimit.for(profile, segment), Limits.figures_of(agreement))
      end.map(&:id)
      Agreement.where(id: ids)
    end

    # Pendente que ninguém pode aprovar (R243, caso do gestor): nenhum usuário com "negociar acordos" no credor cobre a proposta além de quem a montou.
    def nobody_can_approve(tenant_ids)
      Agreement.where(tenant_id: tenant_ids, state: "pending").includes(:segment, :tenant).to_a.reject do |agreement|
        Membership.active.where(tenant_id: agreement.tenant_id).where.not(user_id: agreement.user_id).includes(:user, :profile).any? do |membership|
          membership.profile.permitted?("negotiate_agreements") && membership.profile.permitted?("view_portfolio") && Limits.user_covers?(membership.user, agreement)
        end
      end
    end
  end
end
