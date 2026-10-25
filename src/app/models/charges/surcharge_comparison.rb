module Charges
  # Comparação dos acréscimos informados pelo credor na carga com os calculados pelo CRM (CT-4, R102, R178, R182): só para o gestor ver se o credor
  # mandou o valor já atualizado (E8). Os acréscimos continuam só para conferência: nenhum valor da carteira muda. Os parâmetros, as regras e a
  # política são do credor da carga (MT-8). Total por componente e as 20 maiores diferenças.
  module SurchargeComparison
    LIMIT = 20
    COMPONENTS = %w[correction fine interest fees].freeze # "outros" do credor é comparado com os honorários do CRM
    Sql = Portfolio::Sql

    module_function

    # "Antes de confirmar" (padrão): só as linhas com acréscimos, com o segmento atual do contrato (ou "Demais" se é novo), os pagamentos do título que
    # já existe e o valor e o vencimento do arquivo. É uma aproximação, mas aparece a tempo de desistir da carga.
    def before(import, today: Date.current)
      rows = Sql.rows(<<~SQL, import.tenant_id, import.tenant_id, import.tenant_id, import.id)
        select r.line, r.number, r.amount_cents, r.due_date, r.penalty_cents, r.interest_cents, r.correction_cents, r.other_cents,
               b.id as bill_id, coalesce(c.segment_id, k.segment_id) as segment_id
        from import_rows r
        left join customers cu on cu.tenant_id = ? and cu.document = r.document
        left join bills b on b.tenant_id = ? and b.customer_id = cu.id and b.number = r.number
        left join contracts c on c.id = b.contract_id
        left join contracts k on k.tenant_id = ? and k.code = r.contract
        where r.import_id = ? and r.ok and coalesce(r.penalty_cents, r.interest_cents, r.correction_cents, r.other_cents) is not null
      SQL
      return nil if rows.empty?

      existing = Reader.new(import.tenant, today: today, bill_ids: rows.filter_map { |row| row["bill_id"]&.to_i }.presence || [ 0 ]).to_enum(:each_batch).flat_map(&:itself).index_by(&:bill_id)
      valuation = Valuation.new(tables: RuleSet.tables(import.tenant, today), rules: RuleSet.rules(import.tenant), demais_id: RuleSet.demais_id(import.tenant), versions: RuleHistory.lookup(import.tenant))
      lines = rows.map do |row|
        base = existing[row["bill_id"]&.to_i]
        input = Reader::Input.new(row["bill_id"]&.to_i, 0, 0, row["amount_cents"].to_i, to_date(row["due_date"]), row["segment_id"]&.to_i, base&.payments || [], [], base&.paid || {}, base&.dates || Set.new)
        result = valuation.call(input)
        entry(row["line"], row["number"], { "fine" => row["penalty_cents"], "interest" => row["interest_cents"], "correction" => row["correction_cents"], "fees" => row["other_cents"] }, result)
      end
      summarize(lines, "before")
    end

    # "Depois de confirmar": com o valor atualizado recém-calculado e o segmento exato; guardado no resumo da importação.
    def after(import)
      return unless import.portfolio? && import.tenant.setting.surcharge_comparison_policy_after?

      rows = Sql.rows(<<~SQL, import.id)
        select b.number, s.penalty_cents, s.interest_cents, s.correction_cents, s.other_cents,
               v.principal_cents, v.corrected_principal_cents, v.fine_cents, v.interest_cents as calc_interest, v.fees_cents
        from reported_surcharges s join bills b on b.id = s.bill_id left join bill_valuations v on v.bill_id = b.id
        where s.import_id = ? and coalesce(s.penalty_cents, s.interest_cents, s.correction_cents, s.other_cents) is not null
      SQL
      return if rows.empty?

      lines = rows.map do |row|
        result = Result.new(principal: row["principal_cents"].to_i, corrected_principal: row["corrected_principal_cents"].to_i, fine: row["fine_cents"].to_i,
                            interest: row["calc_interest"].to_i, fees: row["fees_cents"].to_i)
        entry(nil, row["number"], { "fine" => row["penalty_cents"], "interest" => row["interest_cents"], "correction" => row["correction_cents"], "fees" => row["other_cents"] }, result)
      end
      import.update!(summary: import.summary_data.merge(surcharge_comparison: summarize(lines, "after")))
    end

    def entry(line, number, informed, result)
      calculated = { "correction" => result.correction, "fine" => result.fine, "interest" => result.interest, "fees" => result.fees }
      { line: line, number: number, informed: informed.transform_values { |value| value&.to_i }, calculated: calculated }
    end

    def summarize(lines, moment)
      totals = COMPONENTS.map do |name|
        informed = lines.sum { |line| line[:informed][name].to_i }
        calculated = lines.sum { |line| line[:calculated][name].to_i }
        { name: name, informed: informed, calculated: calculated, difference: informed - calculated }
      end
      largest = lines.map do |line|
        informed = COMPONENTS.sum { |name| line[:informed][name].to_i }
        calculated = COMPONENTS.sum { |name| line[:calculated][name].to_i }
        line.merge(informed_total: informed, calculated_total: calculated, difference: informed - calculated)
      end.sort_by { |line| [ -line[:difference].abs, line[:line].to_i ] }.first(LIMIT)
      { moment: moment, lines: lines.size, totals: totals, largest: largest }
    end

    def to_date(value) = value.is_a?(Date) ? value : Date.parse(value.to_s)
  end
end
