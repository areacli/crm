# Limites do perfil por segmento (11, R209, PO-8), dentro das variáveis do segmento: teto de desconto por componente (parcelado e à vista), número máximo de
# parcelas, entrada mínima e, opcionalmente, o teto em reais do desconto total e do valor líquido do acordo (N23). Nascem com o segmento e com o perfil
# (padrão da DA4): quem altera políticas financeiras acompanha o segmento, os outros têm a metade de cada desconto e das parcelas e a mesma entrada mínima.
class AgreementLimit < ApplicationRecord
  belongs_to :tier
  belongs_to :profile

  validates :max_installments, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }
  validates :min_down_payment_pct, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }
  validates :ceiling_discount_cents, :ceiling_value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add(:caps, :invalid) unless Agreements::Caps.valid?(caps) }

  def self.defaults_for(profile, tier)
    if profile.permitted?("change_financial_policies")
      { caps: Agreements::Caps.normalize(tier.agreement_caps), max_installments: tier.agreement_max_installments, min_down_payment_pct: tier.agreement_min_down_payment_pct }
    else
      { caps: Agreements::Caps.half(tier.agreement_caps), max_installments: [ tier.agreement_max_installments / 2, 1 ].max, min_down_payment_pct: tier.agreement_min_down_payment_pct }
    end
  end

  def self.create_for_tier(tier)
    Profile.where(tenant_id: tier.tenant_id).find_each { |profile| create!(tier: tier, profile: profile, **defaults_for(profile, tier)) }
  end

  def self.create_for_profile(profile)
    Tier.where(tenant_id: profile.tenant_id).find_each { |tier| create!(tier: tier, profile: profile, **defaults_for(profile, tier)) }
  end

  # O limite do perfil no segmento; sem linha (perfil ou segmento de antes da tabela), o padrão da DA4.
  def self.for(profile, tier) = find_by(profile_id: profile.id, tier_id: tier.id) || new(tier: tier, profile: profile, **defaults_for(profile, tier))
end
