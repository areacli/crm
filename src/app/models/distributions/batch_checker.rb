module Distributions
  # Conferência do lote (14, R316): resolve quem vai (clientes ou contratos), conta os contratos que a distribuição por cliente leva, o saldo
  # em cobrança, recusa por contrato o que a exclusividade não deixa (listado com a operação) e lista as linhas da planilha não encontradas.
  # Nada é gravado em distribuição; o resultado fica no lote, para a confirmação. Roda como o sistema (fora do papel da requisição), menos a
  # pergunta de quem vai: para o usuário de operação, ela é a da R313, e o que não está pra ele conta como não encontrado.
  class BatchChecker
    SAMPLE = 100

    def initialize(batch) = @batch = batch

    def call
      ids, missing, ambiguous = Operations::Context.acting_as(@batch.user) { resolve }
      raise Refused, I18n.t("distribution_batches.too_many", max: DistributionBatch::MAX) if ids.size > DistributionBatch::MAX

      contracts_by_target = contracts_for(ids)
      blocked = blocked_contracts(contracts_by_target.values.flatten.uniq)
      # A recusa é por contrato (R316); um cliente com algum contrato recusado fica de fora inteiro, porque a distribuição por cliente leva todos.
      accepted = ids.reject { |id| (contracts_by_target.fetch(id, []) & blocked.keys).any? }
      refused = blocked.first(SAMPLE).map { |contract_id, operation| { "contract" => contract_codes[contract_id], "operation" => operation } }
      contracts = contracts_by_target.values_at(*accepted).flatten.uniq - blocked.keys
      @batch.update!(status: "checked", checked_at: Time.current, entries: accepted, summary: {
        "targets" => accepted.size, "contracts" => contracts.size, "extra_contracts" => extra_contracts(accepted, contracts_by_target),
        "balance_cents" => Bill.where(contract_id: contracts, status: "active").sum("amount_cents - paid_cents"),
        "refused_contracts" => blocked.size, "refused" => refused, "missing" => missing.first(SAMPLE), "missing_count" => missing.size,
        "ambiguous" => Array(ambiguous).first(SAMPLE), "ambiguous_count" => Array(ambiguous).size
      })
    rescue Refused, ActiveRecord::QueryCanceled => error
      @batch.update!(status: "failed", summary: { "error" => error.message })
    end

    private
      # Os ids do alvo do lote, e as linhas da planilha sem correspondente.
      def resolve
        tenant = @batch.tenant
        case @batch.kind
        when "segment"
          query = Segments::Compiler.new(tenant).matching(@batch.segment.expression_object)
          [ ActiveRecord::Base.connection.exec_query("select m.id from (#{query.sql}) m", "Distributions", query.binds).rows.flatten, [] ]
        when "file", "selection"
          values = Array(@batch.summary["values"])
          return [ values.map(&:to_i), [] ] if @batch.kind == "selection"

          return resolve_contracts(tenant, values) if @batch.target == "contract"

          found = Customer.where(tenant: tenant, document: values.map { |value| Document.normalize(value) }).pluck(:document, :id).to_h
          values = values.map { |value| Document.normalize(value) }
          [ found.values, values - found.keys ]
        end
      end

      # 17, R421: o código é único dentro do sistema, não do credor. A linha com a coluna `sistema` acha o contrato daquele sistema; sem ela, o código que casa
      # com mais de um contrato é recusado e listado à parte, porque só quem montou a planilha sabe qual era. Cada valor é o código ou o par `[código, sistema]`.
      def resolve_contracts(tenant, values)
        pairs = values.map { |value| Array(value) }
        by_code = Contract.where(tenant: tenant, code: pairs.map(&:first).uniq).pluck(:code, :source_system_id, :id).group_by(&:first)
        systems = SourceSystem.where(tenant_id: tenant.id).to_h { |system| [ system.name.downcase, system.id ] }
        ids, missing, ambiguous = [], [], []
        pairs.each do |code, system|
          found = by_code.fetch(code, [])
          found = found.select { |_code, system_id, _id| system_id == systems[system.downcase] } if system.present?
          case found.size
          when 0 then missing << [ code, system ].compact_blank.join(" · ")
          when 1 then ids << found.first.last
          else ambiguous << code
          end
        end
        [ ids.uniq, missing, ambiguous ]
      end

      def contracts_for(ids)
        return ids.index_with { |id| [ id ] } if @batch.target == "contract"

        ContractCustomer.where(customer_id: ids).pluck(:customer_id, :contract_id).group_by(&:first).transform_values { |rows| rows.map(&:last) }
      end

      # Contratos com outra operação no mesmo período (só com a exclusividade, R312): contrato => nome curto da operação.
      def blocked_contracts(contract_ids)
        return {} if contract_ids.empty? || !@batch.tenant.setting.operation_exclusive

        open = Distribution.open.where(tenant_id: @batch.tenant_id).where.not(operation_id: @batch.operation_id).where.not(source: "rule")
                           .where("starts_on <= COALESCE(?::date, 'infinity'::date) AND (ends_on IS NULL OR ends_on >= ?)", @batch.ends_on, @batch.starts_on)
                           .includes(:operation)
        direct = open.where(contract_id: contract_ids).to_h { |distribution| [ distribution.contract_id, distribution.operation.short_name ] }
        by_customer = open.where.not(customer_id: nil).to_a
        customers = ContractCustomer.where(contract_id: contract_ids, customer_id: by_customer.map(&:customer_id)).pluck(:contract_id, :customer_id)
        names = by_customer.to_h { |distribution| [ distribution.customer_id, distribution.operation.short_name ] }
        customers.each { |contract_id, customer_id| direct[contract_id] ||= names[customer_id] }
        direct
      end

      def extra_contracts(accepted, contracts_by_target)
        return 0 if @batch.target == "contract"

        holders = ContractCustomer.where(customer_id: accepted).where("roles @> '[\"holder\"]'::jsonb OR roles = '[]'::jsonb").distinct.count(:contract_id)
        [ contracts_by_target.values_at(*accepted).flatten.uniq.size - holders, 0 ].max
      end

      def contract_codes = @contract_codes ||= Hash.new { |hash, id| hash[id] = Contract.where(id: id).pick(:code) }
  end
end
