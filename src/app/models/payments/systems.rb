module Payments
  # Os sistemas do credor vistos por um pagamento ou estorno (17, R416, R417c): o sistema de cada linha da planilha (coluna `sistema`) ou de cada evento do
  # webhook genérico, e o pai do pagamento. Lido uma vez por arquivo ou por evento, não por linha.
  class Systems
    attr_reader :crm

    def initialize(tenant_id)
      all = SourceSystem.where(tenant_id: tenant_id).order(:id).to_a
      @by_id = all.index_by(&:id)
      @crm = all.find(&:role_crm?)
      @receiving = all.reject(&:role_crm?)
      # O nome é único no credor sem diferenciar maiúsculas (R397): a coluna é lida do mesmo jeito.
      @by_name = @receiving.index_by { |system| system.name.downcase }
    end

    # Mais de um sistema além do CRM: a coluna `sistema` passa a valer (R416). Com um só, ela é ignorada.
    def multiple? = @receiving.size > 1

    # Algum sistema de id próprio: a coluna `id_titulo` passa a valer (R417).
    def own_ids? = @receiving.any?(&:key_own_id?)

    def find(id) = @by_id[id]

    # O pai do pagamento (R418): o sistema da linha; a linha sem sistema é do CRM.
    def parent(id) = @by_id[id] || crm

    # O sistema de uma linha: `[sistema, nil]`, `[nil, nil]` quando a linha não tem sistema (número `PRM-` ou `ACD-`, que vale em qualquer um) ou
    # `[nil, motivo da recusa]`. `internal`: a linha traz número de promessa ou de acordo.
    def of_line(name, internal:)
      return of_single(internal) unless multiple?

      name = name.to_s.squish
      return (internal ? [ nil, nil ] : [ nil, "sistema obrigatório: o credor tem mais de um sistema" ]) if name.empty?

      named(name)
    end

    # O sistema que uma linha de estorno declara (R416): com um só sistema a coluna é ignorada; vazia, fica para a conferência, que conhece o pagamento.
    def declared(name)
      name = name.to_s.squish
      multiple? && name.present? ? named(name) : [ nil, nil ]
    end

    def paused_message(system) = "o sistema #{system.name} está pausado"

    private
      def named(name)
        system = @by_name[name.downcase]
        return [ nil, "sistema desconhecido: #{name.first(100)}" ] unless system

        system.active? ? [ system, nil ] : [ nil, paused_message(system) ]
      end

      # Com um só sistema, a linha é dele. Pausado, recusa (R398), menos a linha de promessa ou de acordo, que não depende dele.
      def of_single(internal)
        system = @receiving.first
        return [ system, nil ] if system.active?

        internal ? [ nil, nil ] : [ nil, paused_message(system) ]
      end
  end
end
