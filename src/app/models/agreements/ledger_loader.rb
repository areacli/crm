module Agreements
  # Monta o `Ledger` dos títulos de acordo a partir do banco: o acordo (regra de atraso e políticas congeladas, R210) e o que os pagamentos e os abatimentos já
  # cobriram em cada componente. Uma leitura por lote de títulos, nunca por título. Consultas: `payment_allocations (bill_id)` e `abatements (payment_id)` pelos
  # pagamentos do título; os acordos pela chave primária.
  class LedgerLoader
    def initialize(tenant, today: Date.current)
      @tenant = tenant
      @today = today
    end

    # { id do título => Ledger } dos títulos de acordo dados (`bills`: Bill com `kind` de acordo ou da quebra). `agreements`: os acordos já lidos, para não relê-los.
    def call(bills, agreements: nil)
      # O título de estorno (R233) pertence ao acordo de origem só pelos parâmetros congelados dele; não herda os intervalos congelados do acordo.
      bills = bills.select { |bill| bill.agreement_id || bill.origin_agreement_id }
      return {} if bills.empty?

      owner = ->(bill) { bill.agreement_id || bill.origin_agreement_id }
      agreements = (agreements ? agreements.index_by(&:id) : Agreement.where(id: bills.map(&owner).uniq).index_by(&:id))
      missing = bills.map(&owner).uniq - agreements.keys
      agreements.merge!(Agreement.where(id: missing).index_by(&:id)) if missing.any?
      events = events_of(bills.map(&:id))
      bills.to_h do |bill|
        agreement = agreements.fetch(owner.call(bill))
        rule = Charges::AgreementRule.from_storage(agreement.terms.dig("parameters", "late_rule"))
        [ bill.id, Ledger.new(bill, rule: rule, events: events.fetch(bill.id, []), tables: tables_for(agreement, rule),
                              late_enabled: agreement.frozen_policy("late_charges") != "none", early_discount: agreement.frozen_policy("early_payment") != "full_value",
                              frozen: (bill.agreement_id ? agreement.frozen_ranges : [])) ]
      end
    end

    def one(bill) = call([ bill ]).fetch(bill.id)

    # Para um lote de acordos: [{ id do acordo => títulos }, { id do título => Ledger } dos títulos em cobrança ou a cobrar], com uma leitura de títulos e uma de eventos.
    def for_agreements(agreements)
      titles = Bill.where(agreement_id: agreements.map(&:id)).order(:due_date, :id).group_by(&:agreement_id)
      ledgers = call(titles.values.flatten.select { |bill| %w[active scheduled].include?(bill.status) }, agreements: agreements)
      [ titles, ledgers ]
    end

    private
      def tables_for(agreement, rule)
        return nil if rule.index == ""

        @tables ||= {}
        @tables[agreement.id] ||= begin
          policies = agreement.terms["index_policies"] || {}
          current = Charges::Policies.of(@tenant.setting)
          frozen = Charges::Policies.new(policies["missing_index"] || current.missing_index, policies["negative_index"] || current.negative_index, current.old_legal)
          Charges::RuleSet.tables(@tenant, @today, policies: frozen)
        end
      end

      def events_of(bill_ids)
        events = Hash.new { |hash, key| hash[key] = [] }
        { true => "payment_allocations", false => "abatements" }.each do |cash, table|
          rows = Portfolio::Sql.rows(<<~SQL, bill_ids)
            select x.bill_id, x.payment_id, p.paid_on, x.component, sum(x.amount_cents)::bigint as cents
            from #{table} x join payments p on p.id = x.payment_id
            where x.bill_id in (?) group by 1, 2, 3, 4 having sum(x.amount_cents) <> 0 order by p.paid_on, x.payment_id
          SQL
          rows.group_by { |row| [ row["bill_id"].to_i, row["payment_id"].to_i ] }.each do |(bill_id, _), items|
            date = items.first["paid_on"]
            date = Date.parse(date.to_s) unless date.is_a?(Date)
            events[bill_id] << Ledger::Event.new(date, items.to_h { |row| [ row["component"], row["cents"].to_i ] }, cash)
          end
        end
        events
      end
  end
end
