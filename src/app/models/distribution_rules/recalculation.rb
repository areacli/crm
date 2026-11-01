module DistributionRules
  # Recálculo do enquadramento da distribuição de um credor (14, R343, R344): todo dia, depois de cada carga e depois de confirmar uma mudança.
  # O contrato que passa a casar com um item recebe a distribuição de origem "regra" de cada operação do item, desde hoje; o que deixa de casar
  # (ou muda de item, ou passa a ter distribuição à mão) tem a distribuição da regra encerrada com "saiu do segmento", com os efeitos da R317.
  # O contrato com distribuição à mão ou de lote vigente não é tocado (R344). Com a exclusividade, um item tem uma operação só (validado na tela).
  class Recalculation
    def initialize(tenant, actor: nil)
      @tenant = tenant
      @actor = actor
    end

    def apply(today: Date.current)
      items = DistributionRuleItem.where(tenant: @tenant).ordered.to_a
      by_id = items.index_by(&:id)
      Operations::Context.system do
        ApplicationRecord.transaction do
          Portfolio::Sql.execute("select pg_advisory_xact_lock(3, ?)", @tenant.id)
          Assignment.load(@tenant, Assignment.items_of(@tenant), today: today)
          wanted = wanted_pairs(by_id)
          existing = Distribution.open.where(tenant: @tenant, source: "rule").to_a
          closer = Distributions::Closer.new(@actor)
          existing.each do |distribution|
            target = wanted.delete([ distribution.contract_id, distribution.operation_id ])
            if target.nil?
              closer.close(distribution, reason: "left_segment", rebuild: false)
            elsif distribution.rule_item_id != target.id || distribution.exposure != target.exposure
              distribution.update!(rule_item_id: target.id, exposure: target.exposure)
            end
          end
          create(wanted, today)
        end
      end
      Operations::ReachBuilder.new(@tenant).rebuild
    end

    private
      # (contrato, operação) => item, para os contratos atribuídos a um item com operação, sem distribuição à mão ou de lote vigente.
      def wanted_pairs(by_id)
        rows = ActiveRecord::Base.connection.select_rows(<<~SQL)
          select c.contract_id, c.item_key from dist_calc c
           where c.item_key <> 0
             and not exists (select 1 from distributions d where d.tenant_id = #{@tenant.id.to_i} and d.contract_id = c.contract_id and d.source <> 'rule' and d.ended_at is null)
             and not exists (select 1 from distributions d join contract_customers cc on cc.customer_id = d.customer_id
                              where d.tenant_id = #{@tenant.id.to_i} and cc.contract_id = c.contract_id and d.source <> 'rule' and d.ended_at is null)
        SQL
        rows.each_with_object({}) do |(contract_id, item_id), wanted|
          item = by_id[item_id.to_i] or next
          item.operation_ids.each { |operation_id| wanted[[ contract_id.to_i, operation_id ]] = item }
        end
      end

      def create(wanted, today)
        accredited = Accreditation.active.where(tenant: @tenant).pluck(:operation_id)
        entries = []
        wanted.each do |(contract_id, operation_id), item|
          next unless accredited.include?(operation_id)

          distribution = Distribution.create!(tenant: @tenant, operation_id: operation_id, contract_id: contract_id, exposure: item.exposure, starts_on: today,
                                              source: "rule", rule_item_id: item.id, created_by: @actor)
          entries << [ distribution, "created", { after: "regra, item #{item.position}", origin: "task" } ]
        end
        entries.each_slice(1_000) { |slice| Change.record_many!(slice, tenant_id: @tenant.id, actor: @actor) }
      end
  end
end
