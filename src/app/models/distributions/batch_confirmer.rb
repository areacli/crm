module Distributions
  # Confirmação do lote (14, R316): cria as distribuições aceitas na conferência (origem "lote"), recusando de novo o que a exclusividade não
  # deixa naquele momento (alguém pode ter distribuído entre a conferência e a confirmação), e reconstrói o alcance uma vez no fim.
  class BatchConfirmer
    SLICE = 1_000

    def initialize(batch) = @batch = batch

    def call
      model = @batch.target == "contract" ? Contract : Customer
      created = refused = 0
      distributor = Distributor.new(@batch.user)
      @batch.entries.each_slice(SLICE) do |slice|
        ApplicationRecord.transaction do
          model.where(tenant_id: @batch.tenant_id, id: slice).find_each do |target|
            distributor.distribute(tenant: @batch.tenant, operation: @batch.operation, @batch.target.to_sym => target, exposure: @batch.exposure,
                                   starts_on: @batch.starts_on, ends_on: @batch.ends_on, source: "batch", batch_id: @batch.id, rebuild: false)
            created += 1
          rescue Refused
            refused += 1
          end
        end
      end
      @batch.update!(status: "confirmed", confirmed_at: Time.current, summary: @batch.summary.merge("created" => created, "refused_at_confirm" => refused))
      Operations::ReachBuilder.new(@batch.tenant).rebuild
    end
  end
end
