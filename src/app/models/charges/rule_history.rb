module Charges
  # Histórico das regras efetivas dos segmentos, com a data de cada mudança (11, AN1): o encargo até um pagamento fica pela regra vigente nele.
  # Uma versão nasce quando o segmento é criado e quando a regra efetiva dele muda (por edição ou pelo parâmetro do credor que ele herda).
  module RuleHistory
    module_function

    # Grava uma versão para o segmento cuja regra efetiva difere da última guardada. Consulta: `charge_rule_versions (tier_id, since)`.
    def record!(tenant, since: Date.current, rules: RuleSet.rules(tenant))
      latest = ChargeRuleVersion.where(tier_id: rules.keys).order(:tier_id, :since).to_a.group_by(&:tier_id).transform_values(&:last)
      rules.each do |tier_id, rule|
        last = latest[tier_id]
        next if last && Rule.from_storage(last.rule) == rule

        ChargeRuleVersion.upsert({ tier_id: tier_id, since: since, rule: rule.to_h_for_storage }, unique_by: %i[tier_id since])
      end
    end

    # (segmento, data) → a regra vigente na data, ou nil se a data é anterior à primeira versão (vale a regra atual); nil se não há versões.
    def lookup(tenant)
      versions = ChargeRuleVersion.joins(:tier).where(tiers: { tenant_id: tenant.id }).order(:tier_id, :since).pluck(:tier_id, :since, :rule)
                                  .group_by(&:first).transform_values { |rows| rows.map { |_, since, rule| [ since, Rule.from_storage(rule) ] } }
      return nil if versions.empty?

      lambda do |tier_id, date|
        current = nil
        versions.fetch(tier_id, []).each { |since, rule| since <= date ? current = rule : break }
        current
      end
    end
  end
end
