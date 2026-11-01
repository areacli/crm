module Distributions
  # Tarefa diária do credor (14, R311): a distribuição cujo fim passou fica encerrada com o motivo "fim do período", com os efeitos do
  # encerramento (R317). O acesso já respeitava a data antes disto; aqui ficam o registro e o cancelamento das propostas não aceitas.
  class Daily
    def initialize(tenant) = @tenant = tenant

    def call(today: Date.current)
      Operations::Trail.purge(@tenant)
      Distribution.open.where(tenant_id: @tenant.id).where(ends_on: ...today).find_each do |distribution|
        Closer.new(nil).close(distribution, reason: "period_end", rebuild: false)
      end
    end
  end
end
