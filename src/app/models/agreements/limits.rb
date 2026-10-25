module Agreements
  # Alçada do acordo (11, R216, PD2): a proposta nasce aprovada dentro dos limites do perfil de quem monta e pendente fora deles, dentro das variáveis do
  # segmento. Aprova quem tem "negociar acordos" no credor e cujos limites atuais cobririam a proposta se ele mesma a fizesse; nunca quem a montou.
  module Limits
    # O que a alçada compara: a escolha, o desconto por componente (centésimos de ponto), as parcelas, a entrada, o valor líquido e o desconto total.
    Figures = Data.define(:mode, :discounts_bp, :installments, :down_payment_cents, :net_cents, :discount_cents)

    module_function

    def covers?(limit, figures)
      kind = figures.mode == "cash" ? "cash" : "installment"
      return false if figures.discounts_bp.any? { |component, bp| bp > Caps.get(limit.caps, kind, component) * 100 }
      return false if limit.ceiling_discount_cents && figures.discount_cents > limit.ceiling_discount_cents
      return false if limit.ceiling_value_cents && figures.net_cents > limit.ceiling_value_cents
      return true if figures.mode == "cash"

      figures.installments <= limit.max_installments && figures.down_payment_cents * 100 >= figures.net_cents * limit.min_down_payment_pct
    end

    # O limite do usuário no credor do acordo (MT-2): o do perfil dele nele; sem vínculo ativo, nenhum.
    def limit_of(user, agreement)
      membership = Membership.active.where(user_id: user.id, tenant_id: agreement.tenant_id).includes(:profile).first or return
      segment = agreement.segment || Segment.catch_all_of(agreement.tenant)
      AgreementLimit.for(membership.profile, segment)
    end

    # R216: os limites atuais de quem aprova cobririam a proposta se ele mesmo a fizesse.
    def user_covers?(user, agreement)
      limit = limit_of(user, agreement) or return false
      covers?(limit, figures_of(agreement))
    end

    # O que a alçada compara, lido do acordo gravado.
    def figures_of(agreement) = Figures.new(agreement.mode, agreement.discounts_bp, agreement.installments_count, agreement.down_payment_cents, agreement.net_cents, agreement.discount_cents)
  end
end
