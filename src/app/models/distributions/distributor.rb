module Distributions
  # Distribuir, mudar e recolher (14, R311, R312, R317, R344). A permissão 19 já foi conferida pela política. A exclusividade é conferida no
  # ato (distribuir, prorrogar, mudar), por contrato; a distribuição à mão vence a da regra (R344). Toda mudança reconstrói o alcance (0024).
  class Distributor
    def initialize(actor) = @actor = actor

    def distribute(tenant:, operation:, customer: nil, contract: nil, exposure: nil, starts_on: Date.current, ends_on: nil, source: "manual", batch_id: nil,
                   rule_item_id: nil, rebuild: true)
      accreditation = Accreditation.find_by(tenant: tenant, operation: operation)
      raise Refused, I18n.t("distributions.refused.not_active", name: operation.short_name) unless accreditation&.active? && operation.active?

      exposure ||= tenant.setting.operation_default_exposure
      distribution = Distribution.new(tenant: tenant, operation: operation, customer: customer, contract: contract, exposure: exposure, starts_on: starts_on,
                                      ends_on: ends_on, source: source, batch_id: batch_id, rule_item_id: rule_item_id, created_by: @actor)
      ApplicationRecord.transaction do
        clear_conflicts!(distribution)
        distribution.save!
        log(distribution, "created", after: "#{operation.short_name} · #{distribution.target_label} · #{exposure}")
      end
      Operations::ReachBuilder.new(tenant).rebuild if rebuild
      distribution
    end

    # R317 da 14 (mudar): exposição e fim; o início só enquanto agendada. Passa pela exclusividade de novo.
    def change(distribution, exposure:, ends_on:, starts_on: distribution.starts_on)
      raise Refused, I18n.t("distributions.refused.ended") if distribution.ended_at
      raise Refused, I18n.t("distributions.refused.past_end") if ends_on.present? && ends_on < Date.current
      raise Refused, I18n.t("distributions.refused.started") if starts_on != distribution.starts_on && distribution.starts_on <= Date.current

      before = "#{distribution.exposure} · #{distribution.starts_on} a #{distribution.ends_on || 'sem fim'}"
      ApplicationRecord.transaction do
        distribution.assign_attributes(exposure: exposure, ends_on: ends_on, starts_on: starts_on)
        clear_conflicts!(distribution)
        distribution.save!
        log(distribution, "changed", before: before, after: "#{exposure} · #{starts_on} a #{ends_on || 'sem fim'}")
      end
      Operations::ReachBuilder.new(distribution.tenant).rebuild
      distribution
    end

    # Contratos que a distribuição alcança hoje: o próprio, ou os do cliente (titular ou responsável).
    def self.contract_ids_for(distribution)
      return [ distribution.contract_id ] if distribution.contract_id

      ContractCustomer.where(customer_id: distribution.customer_id).pluck(:contract_id)
    end

    private
      # R312 e R344: com a exclusividade, outra operação com distribuição aberta no mesmo período sobre o mesmo contrato recusa a nova; a da regra,
      # diante de uma distribuição à mão, se encerra ("distribuído à mão").
      def clear_conflicts!(distribution)
        # O RLS esconde do usuário de operação as distribuições das outras: a exclusividade olha todas, como o sistema (14, R312).
        Operations::Context.system do
          return unless distribution.tenant.setting.operation_exclusive

          contracts = self.class.contract_ids_for(distribution)
          return if contracts.empty?

          others = Distribution.open.where(tenant_id: distribution.tenant_id).where.not(operation_id: distribution.operation_id).where.not(id: distribution.id)
                               .where("starts_on <= COALESCE(?::date, 'infinity'::date) AND (ends_on IS NULL OR ends_on >= ?)", distribution.ends_on, distribution.starts_on)
                               .where("contract_id IN (:ids) OR customer_id IN (SELECT customer_id FROM contract_customers WHERE contract_id IN (:ids))", ids: contracts)
                               .includes(:operation)
          rule = others.select { |other| other.source == "rule" }
          if distribution.source != "rule" && rule.any?
            rule.each { |other| Closer.new(@actor).close(other, reason: "manual_override", rebuild: false) }
            others = others.reject { |other| other.source == "rule" }
          end
          conflict = others.first or return
          raise Refused, I18n.t("distributions.refused.exclusive", target: distribution.target_label, name: conflict.operation.short_name,
                                                                     period: conflict.ends_on ? "até #{I18n.l(conflict.ends_on)}" : "sem fim")
        end
      end

      def log(distribution, event, **fields) = Change.record!(distribution, event, tenant_id: distribution.tenant_id, actor: @actor, origin: @actor ? "screen" : "task", **fields)
  end
end
