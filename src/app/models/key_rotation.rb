# Rotação das chaves do Active Record Encryption (12, R254 a R256). A ÚLTIMA chave da lista cifra e todas decifram; o cabeçalho do texto
# cifrado guarda o identificador da chave que o cifrou (`store_key_references`). Esta classe:
#   - `status`: por modelo e atributo cifrado, quantos registros NÃO estão na chave atual (os sem referência também contam);
#   - `call`: regrava, em lotes de 500, só o que não está na chave atual. É retomável: o que já foi regravado não é tocado, e uma execução
#     interrompida é fechada como falha pela seguinte. Cada execução é um TaskRun global.
class KeyRotation
  NAME = "encryption_rotation"
  BATCH_SIZE = 500

  Pending = Data.define(:model, :attribute, :total, :pending)

  # `after_batch`: gancho chamado com o número do lote (os testes o usam para simular a morte do processo).
  def initialize(batch_size: BATCH_SIZE, after_batch: nil)
    @batch_size = batch_size
    @after_batch = after_batch
  end

  # Atributos cifrados de todos os modelos: [modelo, nome do atributo].
  def self.targets
    Rails.application.eager_load! unless Rails.application.config.eager_load
    ApplicationRecord.descendants.reject(&:abstract_class?).flat_map { |model| Array(model.try(:encrypted_attributes)).map { |attribute| [ model, attribute.to_s ] } }
  end

  def self.current_key_id = ActiveRecord::Encryption.key_provider.encryption_key.id

  def status
    current = self.class.current_key_id
    self.class.targets.map do |model, attribute|
      total = pending = 0
      model.unscoped.in_batches(of: @batch_size) do |batch|
        batch.each do |record|
          next if record.read_attribute_before_type_cast(attribute).nil?

          total += 1
          pending += 1 if stale?(record, attribute, current)
        end
      end
      Pending.new(model: model.name, attribute: attribute, total: total, pending: pending)
    end
  end

  def pending_total = status.sum(&:pending)

  def call
    close_interrupted_runs
    run = TaskRun.create!(name: NAME, started_at: Time.current)
    current = self.class.current_key_id
    processed = failed = batches = 0
    self.class.targets.group_by(&:first).each do |model, pairs|
      attributes = pairs.map(&:last)
      model.unscoped.in_batches(of: @batch_size) do |batch|
        model.transaction do
          batch.each do |record|
            next unless attributes.any? { |attribute| stale?(record, attribute, current) }

            begin
              record.encrypt
              processed += 1
            rescue ActiveRecord::Encryption::Errors::Decryption
              failed += 1
            end
          end
        end
        @after_batch&.call(batches += 1)
      end
    end
    remaining = pending_total
    run.update!(status: (failed.zero? && remaining.zero? ? "succeeded" : "failed"), finished_at: Time.current, processed: processed, failed: failed,
                note: "Restam #{remaining} registro(s) fora da chave atual.", error_kind: (failed.positive? ? "Decryption" : nil))
    run
  end

  private
    # Execução que morreu no meio fica "em andamento" para sempre; a próxima a fecha (R255).
    def close_interrupted_runs
      TaskRun.where(name: NAME, status: "running").update_all(status: "failed", finished_at: Time.current, error_kind: "Interrupted", note: "Interrompida antes de terminar.")
    end

    def stale?(record, attribute, current)
      raw = record.read_attribute_before_type_cast(attribute)
      return false if raw.nil?

      key_id(raw) != current
    end

    def key_id(raw)
      ActiveRecord::Encryption.message_serializer.load(raw).headers.encrypted_data_key_id
    rescue StandardError
      nil
    end
end
