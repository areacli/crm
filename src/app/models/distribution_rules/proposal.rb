module DistributionRules
  # Uma mudança do enquadramento da distribuição ainda não confirmada (14, R345): a lista nova de itens, em ordem, assinada com a versão do
  # enquadramento em que foi montada (a conferência velha é recusada).
  class Proposal
    Item = Data.define(:segment_id, :operation_ids, :exposure)

    attr_reader :tenant, :items, :version, :started_at

    def initialize(tenant, items, version, started_at: nil)
      @tenant = tenant
      @items = items
      @version = version
      @started_at = started_at
    end

    def self.current(tenant)
      items = DistributionRuleItem.where(tenant: tenant).ordered.map { |item| Item.new(item.segment_id, item.operation_ids.sort, item.exposure) }
      new(tenant, items, tenant.setting.distribution_rules_version)
    end

    def self.verifier = Rails.application.message_verifier("distribution_rules")

    def self.from_token(tenant, token)
      data = verifier.verify(token)
      raise Distributions::Refused, I18n.t("distribution_rules.stale") unless data["tenant_id"] == tenant.id

      new(tenant, data["items"].map { |item| Item.new(item["segment_id"], item["operation_ids"], item["exposure"]) }, data["version"], started_at: data["started_at"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Distributions::Refused, I18n.t("distribution_rules.stale")
    end

    def token = self.class.verifier.generate({ "tenant_id" => tenant.id, "version" => version, "started_at" => Time.current.iso8601, "items" => items.map(&:to_h).map { |item| item.transform_keys(&:to_s) } }, expires_in: 30.minutes)

    def with_included(segment_id, operation_ids, exposure, position) = changed { |list| list.insert(position.clamp(0, list.size), Item.new(segment_id.to_i, operation_ids.map(&:to_i).sort, exposure)) }
    def with_changed(index, operation_ids, exposure) = changed { |list| list[index] = Item.new(list[index].segment_id, operation_ids.map(&:to_i).sort, exposure) }
    def with_removed(index) = changed { |list| list.delete_at(index) }
    def with_moved(index, offset) = changed { |list| (target = index + offset).between?(0, list.size - 1) && (list[index], list[target] = list[target], list[index]) }

    # Recusas da R342: segmento de contratos, ativo, uma vez só; operação credenciada e ativa; com a exclusividade, uma operação por item.
    def validate!
      segments = Segment.where(tenant: tenant, id: items.map(&:segment_id)).index_by(&:id)
      accredited = Accreditation.active.where(tenant: tenant).pluck(:operation_id)
      raise Distributions::Refused, I18n.t("distribution_rules.refused.duplicate") if items.map(&:segment_id).uniq.size != items.size

      items.each do |item|
        segment = segments[item.segment_id]
        raise Distributions::Refused, I18n.t("distribution_rules.refused.segment") unless segment&.active? && segment.subject == "contracts"
        raise Distributions::Refused, I18n.t("distribution_rules.refused.operations") if item.operation_ids.empty? || (item.operation_ids - accredited).any?
        raise Distributions::Refused, I18n.t("distribution_rules.refused.exclusive") if tenant.setting.operation_exclusive && item.operation_ids.size > 1
        raise Distributions::Refused, I18n.t("distribution_rules.refused.exposure") unless Distribution::EXPOSURES.include?(item.exposure)
      end
      self
    end

    private
      def changed
        list = items.dup
        yield list
        self.class.new(tenant, list, version).validate!
      end
  end
end
