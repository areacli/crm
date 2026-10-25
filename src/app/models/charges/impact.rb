module Charges
  # Conferência do impacto de uma mudança de encargos (R163, R180, R181): o valor atualizado por segmento, antes e depois, em memória, sem gravar.
  # Mudança na regra de um segmento (ou no parâmetro do credor que ele herda): só os títulos dos contratos que passaram por ele. Mudança de política
  # que muda valores: a base toda do credor. O "antes" é o recálculo de hoje já gravado, quando não há outro em andamento (medido na V4: calcular a
  # carteira duas vezes levava a conferência perto do limite); título fora dele é calculado.
  class Impact
    VALUE_POLICIES = %w[missing_index_policy negative_index_policy old_legal_interest_policy].freeze

    Row = Data.define(:segment_id, :name, :customers, :before_cents, :after_cents) do
      def difference_cents = after_cents - before_cents
    end

    def initialize(proposal, today: Date.current)
      @proposal = proposal
      @tenant = proposal.tenant
      @today = today
    end

    def changes_values? = whole_base? || changed_segment_ids.any?

    def rows
      return [] unless changes_values?

      @rows ||= compute
    end

    # Segmentos com multa acima de 2% que aceitam pessoa física, com a regra nova ou mudada: aviso do CDC, art. 52, § 1º (R161). Não impede a gravação.
    def cdc_warnings
      @proposal.entries.filter_map do |entry|
        rule = @proposal.rule_of(entry)
        id = entry[:id].to_i
        next unless rule.fine * 100 > Segment::CDC_FINE_LIMIT && entry[:person_type] != "company"
        next if id.positive? && current_rules[id] == rule

        entry[:name]
      end
    end

    def total_difference_cents = rows.sum(&:difference_cents)

    private
      def current_rules = @current_rules ||= RuleSet.rules(@tenant)

      def proposed_rules
        @proposed_rules ||= @proposal.entries.select { |entry| entry[:id].to_i.positive? }.to_h { |entry| [ entry[:id].to_i, @proposal.rule_of(entry) ] }
      end

      def changed_segment_ids = @changed_segment_ids ||= proposed_rules.select { |id, rule| current_rules[id] != rule }.keys

      def whole_base? = VALUE_POLICIES.any? { |name| @proposal.charges[name].to_s != @tenant.setting[name].to_s }

      def compute
        demais = RuleSet.demais_id(@tenant)
        rates = RuleSet.rates(@tenant)
        before = Valuation.new(tables: RuleSet.tables(@tenant, @today, rates: rates), rules: current_rules, demais_id: demais, versions: versions)
        after_policies = Policies.new(@proposal.charges["missing_index_policy"], @proposal.charges["negative_index_policy"], @proposal.charges["old_legal_interest_policy"])
        after = Valuation.new(tables: RuleSet.tables(@tenant, @today, policies: after_policies, rates: rates), rules: current_rules.merge(proposed_rules), demais_id: demais, versions: versions)
        status = Recalculation.status(@tenant)
        stored_today = status[:calculated_on] == @today && !status[:running]
        sums = Hash.new { |hash, key| hash[key] = [ Set.new, 0, 0 ] }
        Reader.new(@tenant, today: @today, segment_ids: whole_base? ? nil : changed_segment_ids, unsegmented: changed_segment_ids.include?(demais)).each_batch do |batch|
          stored = stored_today ? stored_totals(batch.first.bill_id, batch.last.bill_id) : {}
          batch.each do |input|
            was = stored[input.bill_id] || before.call(input).total
            will = after.call(input).total
            entry = sums[input.segment_id || demais]
            entry[0] << input.customer_id if was != will
            entry[1] += was
            entry[2] += will
          end
        end
        order = @proposal.entries.map { |entry| entry[:id].to_i }
        sums.sort_by { |id, _| order.index(id) || order.size }.map do |id, (customers, was, will)|
          Row.new(id, @proposal.name_of(id), customers.size, was, will)
        end
      end

      # O recálculo de hoje já gravado, por intervalo de chaves (o lote é um intervalo): uma lista de 20 mil números na consulta custava mais que o cálculo.
      def stored_totals(low, high)
        ActiveRecord::Base.connection.select_rows("select bill_id, total_cents from bill_valuations where bill_id between #{low.to_i} and #{high.to_i}").to_h
      end

      def versions = @versions ||= RuleHistory.lookup(@tenant)
  end
end
