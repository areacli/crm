# Alçada: o prazo máximo, em dias até a data prometida, que um perfil dá sozinho num segmento (R190). Nasce com o segmento e com o perfil; subir o
# prazo do segmento não sobe alçada nenhuma, e baixá-lo baixa junto as que passavam dele.
class PromiseLimit < ApplicationRecord
  belongs_to :segment
  belongs_to :profile

  validates :max_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }

  # Padrão da R190: quem altera políticas financeiras (o Gestor) tem o prazo do segmento; os outros, até 30 dias ou o prazo do segmento, o menor.
  def self.default_days(profile, segment)
    profile.permitted?("change_financial_policies") ? segment.promise_max_days : [ 30, segment.promise_max_days ].min
  end

  def self.create_for_segment(segment)
    Profile.where(tenant_id: segment.tenant_id).find_each { |profile| create!(segment: segment, profile: profile, max_days: default_days(profile, segment)) }
  end

  def self.create_for_profile(profile)
    Segment.where(tenant_id: profile.tenant_id).find_each { |segment| create!(segment: segment, profile: profile, max_days: default_days(profile, segment)) }
  end
end
