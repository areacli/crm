module Queues
  # Uma mudança do enquadramento da fila de um sujeito ainda não confirmada (15, R357): os itens em ordem, assinada com a versão do enquadramento
  # do credor (a conferência velha é recusada). Os itens guardam o id da fila que já existe, para que grupos e posições continuem ligados a ela.
  class Proposal
    Item = Data.define(:id, :segment_id, :name, :delivers)

    attr_reader :tenant, :subject, :items, :version, :started_at

    def initialize(tenant, subject, items, version, started_at: nil)
      @tenant = tenant
      @subject = subject
      @items = items
      @version = version
      @started_at = started_at
    end

    def self.current(tenant, subject)
      items = WorkQueue.framing(tenant, subject).reject(&:catch_all).map { |queue| Item.new(queue.id, queue.segment_id, queue.name, queue.delivers) }
      new(tenant, subject, items, tenant.setting.queue_rules_version)
    end

    def self.verifier = Rails.application.message_verifier("queue_rules")

    def self.from_token(tenant, token)
      data = verifier.verify(token)
      raise Refused, I18n.t("queues.stale") unless data["tenant_id"] == tenant.id

      items = data["items"].map { |item| Item.new(item["id"], item["segment_id"], item["name"], item["delivers"]) }
      new(tenant, data["subject"], items, data["version"], started_at: data["started_at"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Refused, I18n.t("queues.stale")
    end

    def token
      payload = { "tenant_id" => tenant.id, "subject" => subject, "version" => version, "started_at" => Time.current.iso8601, "items" => items.map { |item| item.to_h.transform_keys(&:to_s) } }
      self.class.verifier.generate(payload, expires_in: 30.minutes)
    end

    def with_included(segment_id, name, delivers, position)
      changed { |list| list.insert(position.to_i.clamp(0, list.size), Item.new(nil, segment_id.to_i, name.to_s.strip, delivers)) }
    end

    def with_changed(index, segment_id, name, delivers) = changed { |list| list[index] = list.fetch(index).with(segment_id: segment_id.to_i, name: name.to_s.strip, delivers: delivers) }
    def with_removed(index) = changed { |list| list.delete_at(index) }
    def with_moved(index, offset) = changed { |list| (target = index + offset).between?(0, list.size - 1) && (list[index], list[target] = list[target], list[index]) }

    # Segmento ativo, do sujeito do enquadramento, uma vez só; nome obrigatório e único.
    def validate!
      segments = Segment.where(tenant: tenant, id: items.map(&:segment_id)).index_by(&:id)
      raise Refused, I18n.t("queues.refused.duplicate") if items.map(&:segment_id).uniq.size != items.size
      raise Refused, I18n.t("queues.refused.name") if items.any? { |item| item.name.blank? } || items.map { _1.name.downcase }.uniq.size != items.size

      items.each do |item|
        segment = segments[item.segment_id]
        raise Refused, I18n.t("queues.refused.segment") unless segment&.active? && segment.subject == subject
      end
      self
    end

    private
      def changed
        list = items.dup
        yield list
        self.class.new(tenant, subject, list, version).validate!
      end
  end
end
