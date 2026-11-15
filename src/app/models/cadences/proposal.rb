module Cadences
  # Uma mudança da régua ligada ainda não confirmada (21, R442): as operações do `Editor`, assinadas com a versão da régua e o último salvamento
  # dos segmentos das raias. A conferência velha (a régua ou um segmento mudou depois) é recusada.
  class Proposal
    attr_reader :cadence, :operations, :version, :segments_at

    def initialize(cadence, operations, version: cadence.version, segments_at: Proposal.segments_at(cadence))
      @cadence = cadence
      @operations = operations.map { |op| op.to_h.stringify_keys }
      @version = version
      @segments_at = segments_at
    end

    def self.segments_at(cadence) = Segment.where(id: cadence.lanes.map(&:segment_id).compact).maximum(:updated_at)&.iso8601(6)

    def self.verifier = Rails.application.message_verifier("cadence_changes")

    def self.from_token(cadence, token)
      data = verifier.verify(token)
      raise Refused, I18n.t("cadences.errors.stale") unless data["cadence_id"] == cadence.id

      new(cadence, data["operations"], version: data["version"], segments_at: data["segments_at"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Refused, I18n.t("cadences.errors.stale")
    end

    def token
      payload = { "cadence_id" => cadence.id, "version" => version, "segments_at" => segments_at, "operations" => operations }
      self.class.verifier.generate(payload, expires_in: 30.minutes)
    end

    def stale? = cadence.reload.version != version || Proposal.segments_at(cadence) != segments_at
  end
end
