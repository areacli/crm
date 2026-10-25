module Segments
  # Como ficariam os segmentos de um credor depois de uma mudança (R154): a lista em ordem, com a política de produto. Nada é gravado até a
  # confirmação. A proposta viaja entre as duas telas assinada, junto com a versão dos segmentos, para recusar conferência velha.
  class Proposal
    PURPOSE = :segments_proposal
    NEW_ID = -1

    attr_reader :tenant, :entries, :policy, :version, :charges

    # `charges`: os parâmetros e as políticas de encargos do credor (09, R160, R163, R180 a R182), chave => valor em texto.
    def initialize(tenant, entries:, policy:, version:, charges: nil)
      @tenant = tenant
      @entries = entries
      @policy = policy
      @version = version
      @charges = charges || self.class.charges_of(tenant.setting)
    end

    def self.charges_of(setting) = TenantSetting::CHARGE_FIELDS.index_with { |name| setting[name].to_s }

    def self.current(tenant)
      setting = tenant.setting
      new(tenant, entries: Segment.where(tenant_id: tenant.id).ordered.map { |segment| entry_of(segment) }, policy: setting.segment_product_policy, version: setting.segments_version)
    end

    def self.entry_of(segment)
      { id: segment.id, name: segment.name, active: segment.active, catch_all: segment.catch_all }.merge(segment.criteria.symbolize_keys)
        .merge(Segment::CHARGE_FIELDS.index_with { |field| segment[field] })
    end

    def self.from_token(tenant, token)
      data = Rails.application.message_verifier(:segments).verified(token, purpose: PURPOSE)
      raise Refused, I18n.t("segments.errors.invalid_token") unless data && data["tenant_id"] == tenant.id

      new(tenant, entries: data["entries"].map { |entry| entry.symbolize_keys }, policy: data["policy"], version: data["version"], charges: data["charges"])
    end

    def token
      Rails.application.message_verifier(:segments).generate({ "tenant_id" => tenant.id, "version" => version, "policy" => policy, "entries" => entries, "charges" => charges },
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

    def with_charges(changes) = copy(charges: charges.merge(changes.stringify_keys))

    # Os parâmetros do credor e as regras de cada segmento como o cálculo os lê (09, R160), com o que a proposta muda.
    def params = charges.slice(*TenantSetting::CHARGE_PARAMS).symbolize_keys

    def rule_of(entry) = Charges::Rule.build(entry, params)

    def name_of(id) = id.nil? ? I18n.t("segments.none") : entries.find { |entry| entry[:id] == id }&.fetch(:name) || Segment.find_by(id: id)&.name || I18n.t("segments.none")

    private
      def copy(entries: self.entries, policy: self.policy, charges: self.charges) = self.class.new(tenant, entries: entries, policy: policy, version: version, charges: charges)
  end
end
