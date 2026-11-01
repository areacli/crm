module Tiers
  # Como ficaria o enquadramento financeiro de um credor depois de uma mudança (13, R272): os itens em ordem, cada um com o segmento (nome e
  # árvore) e as regras, e os parâmetros e políticas de encargos do credor. Nada é gravado até a confirmação. A proposta viaja assinada entre a
  # conferência e a confirmação, junto com a versão do enquadramento, para recusar conferência velha.
  class Proposal
    PURPOSE = :tiers_proposal
    NEW_ID = -1

    attr_reader :tenant, :entries, :version, :charges, :segments

    # `entries`: [{ id:, segment_id:, name:, expression:, company_only:, active:, catch_all:, copy_from:, campos das regras }].
    # `segments`: as mudanças de segmento que a proposta leva ({ "id" => { "name", "expression", "active" } }), aplicadas na confirmação.
    def initialize(tenant, entries:, version:, charges: nil, segments: {})
      @tenant = tenant
      @entries = entries
      @version = version
      @charges = charges || self.class.charges_of(tenant.setting)
      @segments = segments
    end

    def self.charges_of(setting) = TenantSetting::CHARGE_FIELDS.index_with { |name| setting[name].to_s }

    def self.current(tenant)
      tiers = Tier.financial.where(tenant_id: tenant.id).includes(:segment).ordered.to_a
      new(tenant, entries: tiers.map { |tier| entry_of(tier) }, version: tenant.setting.tiers_version)
    end

    def self.entry_of(tier, segment: tier.segment)
      { id: tier.id, segment_id: tier.segment_id, name: tier.name, expression: segment&.expression, company_only: tier.company_only?,
        active: tier.active, catch_all: tier.catch_all }.merge(Tier::RULE_FIELDS.index_with { |field| tier[field] })
    end

    def self.from_token(tenant, token)
      data = Rails.application.message_verifier(:tiers).verified(token, purpose: PURPOSE)
      raise Refused, I18n.t("tiers.errors.invalid_token") unless data && data["tenant_id"] == tenant.id

      new(tenant, entries: data["entries"].map(&:symbolize_keys), version: data["version"], charges: data["charges"], segments: data["segments"] || {})
    end

    def token
      Rails.application.message_verifier(:tiers).generate({ "tenant_id" => tenant.id, "version" => version, "entries" => entries, "charges" => charges, "segments" => segments },
                                                          expires_in: 30.minutes, purpose: PURPOSE)
    end

    # Os itens que o cálculo avalia, em ordem: [[id, Expression]], e o da trilha padrão.
    def classified = entries.select { |entry| entry[:active] && !entry[:catch_all] }.map { |entry| [ entry[:id], Segments::Expression.new(entry[:expression]) ] }

    def catch_all_id = entries.find { |entry| entry[:catch_all] }.fetch(:id)

    # R266: inclui o segmento antes do item `before_id` (ou antes do "Demais"), com as regras copiadas do item `copy_from_id` (SG15).
    def with_included(segment, before_id:, copy_from_id:)
      source = entries.find { |entry| entry[:id] == copy_from_id } || entries.find { |entry| entry[:catch_all] }
      entry = source.slice(*Tier::RULE_FIELDS).merge(id: NEW_ID, segment_id: segment.id, name: segment.name, expression: segment.expression,
                                                     company_only: false, active: true, catch_all: false, copy_from: source[:id])
      list = entries.dup
      index = list.index { |item| item[:id] == before_id && !item[:catch_all] } || list.index { |item| item[:catch_all] }
      list.insert(index, entry)
      copy(entries: list)
    end

    # Tirar do enquadramento (R266): o item fica inativo; quem estava nele vai para o próximo que casar.
    def with_removed(id) = copy(entries: entries.map { |entry| entry[:id] == id && !entry[:catch_all] ? entry.merge(active: false) : entry })

    def with_moved(id, direction)
      list = entries.select { |entry| entry[:active] || entry[:catch_all] }
      rest = entries - list
      index = list.index { |entry| entry[:id] == id }
      target = direction == "up" ? index.to_i - 1 : index.to_i + 1
      return self if index.nil? || list[index][:catch_all] || target.negative? || target >= list.size || list[target][:catch_all]

      list[index], list[target] = list[target], list[index]
      copy(entries: list + rest)
    end

    # Regras de um item (09, 10, 11; R272): encargos, prazo da promessa e variáveis e parâmetros de acordo.
    def with_rules(id, changes) = copy(entries: entries.map { |entry| entry[:id] == id ? entry.merge(changes.symbolize_keys.slice(*Tier::RULE_FIELDS)) : entry })

    # Mudança num segmento usado (R272, R273): nome, árvore ou situação. Desativado, os itens dele saem da avaliação.
    def with_segment(segment)
      list = entries.map do |entry|
        next entry unless entry[:segment_id] == segment.id

        entry.merge(name: segment.name, expression: segment.expression, active: entry[:active] && segment.active)
      end
      copy(entries: list, segments: segments.merge(segment.id.to_s => { "name" => segment.name, "expression" => segment.expression, "active" => segment.active }))
    end

    def with_charges(changes) = copy(charges: charges.merge(changes.stringify_keys))

    # Os parâmetros do credor e as regras de cada item como o cálculo os lê (09, R160), com o que a proposta muda.
    def params = charges.slice(*TenantSetting::CHARGE_PARAMS).symbolize_keys

    def rule_of(entry) = Charges::Rule.build(entry, params)

    def name_of(id) = id.nil? ? I18n.t("tiers.none") : entries.find { |entry| entry[:id] == id }&.fetch(:name) || Tier.find_by(id: id)&.name || I18n.t("tiers.none")

    private
      def copy(entries: self.entries, charges: self.charges, segments: self.segments) = self.class.new(tenant, entries: entries, version: version, charges: charges, segments: segments)
  end
end
