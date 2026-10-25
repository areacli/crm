module Promises
  # Alçada de prazo (R190, R191): o segmento que vale é o do contrato (A10), e o prazo que o usuário dá sozinho é o do perfil dele no credor da promessa
  # (MT-3, MT-21), dentro da política do segmento.
  module Limits
    module_function

    # O segmento do contrato; contrato sem segmento vale como "Demais" (13, decisão 13).
    def segment_of(contract) = contract.segment || Segment.catch_all_of(contract.tenant)

    # Prazo máximo, em dias a partir do contato, que a política do segmento aceita (R189): nenhuma promessa passa dele, nem com aprovação.
    def ceiling(segment) = segment.promise_max_days

    # Dias que o usuário dá sozinho: a alçada do perfil dele no segmento, nunca acima do prazo do segmento. Sem vínculo ativo, zero.
    def days_for(user, tenant_id, segment)
      profile_id = Membership.active.where(user_id: user.id, tenant_id: tenant_id).pick(:profile_id)
      return 0 unless profile_id

      limit = PromiseLimit.where(segment_id: segment.id, profile_id: profile_id).pick(:max_days) || PromiseLimit.default_days(Profile.find(profile_id), segment)
      [ limit, ceiling(segment) ].min
    end

    # R192: a alçada de quem aprova cobriria o prazo pedido.
    def covers?(user, promise)
      segment = promise.segment || Segment.catch_all_of(promise.tenant)
      days_for(user, promise.tenant_id, segment) >= promise.days_asked
    end
  end
end
