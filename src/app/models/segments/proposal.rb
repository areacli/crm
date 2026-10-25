module Segments
  # Como ficariam os segmentos de um credor depois de uma mudança (R154): a lista em ordem, com a política de produto. Nada é gravado até a
  # confirmação. A proposta viaja entre as duas telas assinada, junto com a versão dos segmentos, para recusar conferência velha.
  class Proposal
    PURPOSE = :segments_proposal
    NEW_ID = -1

    attr_reader :tenant, :entries, :policy, :version

    def initialize(tenant, entries:, policy:, version:)
      @tenant = tenant
      @entries = entries
      @policy = policy
      @version = version
    end

    def self.current(tenant)
      setting = tenant.setting
      new(tenant, entries: Segment.where(tenant_id: tenant.id).ordered.map { |segment| entry_of(segment) }, policy: setting.segment_product_policy, version: setting.segments_version)
    end

    def self.entry_of(segment)
      { id: segment.id, name: segment.name, active: segment.active, catch_all: segment.catch_all }.merge(segment.criteria.symbolize_keys)
    end

    def self.from_token(tenant, token)
      data = Rails.application.message_verifier(:segments).verified(token, purpose: PURPOSE)
      raise Refused, I18n.t("segments.errors.invalid_token") unless data && data["tenant_id"] == tenant.id

      new(tenant, entries: data["entries"].map { |entry| entry.symbolize_keys }, policy: data["policy"], version: data["version"])
    end

    def token
      Rails.application.message_verifier(:segments).generate({ "tenant_id" => tenant.id, "version" => version, "policy" => policy, "entries" => entries },
                                                             expires_in: 30.minutes, purpose: PURPOSE)
    end

    # Segmento novo entra antes do "Demais" (no fim da lista dos comuns). `segment` é um Segment ainda não gravado e já validado.
    def with_created(segment)
      common = entries.reject { |entry| entry[:catch_all] }
      rest = entries.select { |entry| entry[:catch_all] }
      copy(entries: common + [ self.class.entry_of(segment).merge(id: NEW_ID) ] + rest)
    end

    def with_updated(segment) = copy(entries: entries.map { |entry| entry[:id] == segment.id ? self.class.entry_of(segment) : entry })

    def with_active(id, active) = copy(entries: entries.map { |entry| entry[:id] == id && !entry[:catch_all] ? entry.merge(active: active) : entry })

    def with_moved(id, direction)
      list = entries.dup
      index = list.index { |entry| entry[:id] == id }
      target = direction == "up" ? index - 1 : index + 1
      return self if index.nil? || list[index][:catch_all] || target.negative? || target >= list.size || list[target][:catch_all]

      list[index], list[target] = list[target], list[index]
      copy(entries: list)
    end

    def with_policy(policy) = copy(policy: policy)

    def name_of(id) = id.nil? ? I18n.t("segments.none") : entries.find { |entry| entry[:id] == id }&.fetch(:name) || Segment.find_by(id: id)&.name || I18n.t("segments.none")

    private
      def copy(entries: self.entries, policy: self.policy) = self.class.new(tenant, entries: entries, policy: policy, version: version)
  end
end
