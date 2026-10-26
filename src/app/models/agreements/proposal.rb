module Agreements
  # Gravação da proposta (11, R211 a R218): roda a simulação dentro da transação, confere de novo que os títulos continuam livres e em cobrança, dá o número,
  # decide pela alçada se nasce aprovada ou pendente (R216), congela tudo o que é do acordo (R210) e prende os títulos (R218). A proposta não se edita.
  class Proposal
    def initialize(actor, customer)
      @actor = actor
      @customer = customer
    end

    # `input`: `Simulation::Input`. Devolve o acordo gravado, ou levanta Refused com a primeira recusa da R215.
    def create(input, today: Date.current)
      agreement = nil
      ApplicationRecord.transaction do
        tenant = @customer.tenant
        # Trava consultiva por cliente: duas propostas ao mesmo tempo sobre os mesmos títulos não passam as duas (o índice único parcial é a segunda guarda).
        Portfolio::Sql.one("select pg_advisory_xact_lock(?, ?)::text as locked", tenant.id, @customer.id)
        quote = Simulation.new(user: @actor, customer: @customer, input: input, today: today).call
        raise Refused, quote.error if quote.error

        number = Numbering.next_for(tenant.id)
        # R218: a proposta substituída é cancelada antes, com o número da nova, e libera os títulos que o índice único prende.
        replaced_proposals(quote, input).each { |old| Canceller.new(@actor).cancel(old, I18n.t("agreements.canceled.replaced", number: number), kind: "replaced") }
        agreement = persist(quote, input, today, number)
      end
      agreement
    rescue ActiveRecord::RecordNotUnique
      raise Refused, I18n.t("agreements.refused.bill_taken")
    end

    private
      def replaced_proposals(quote, input)
        return [] unless input.replace

        ids = quote.rows.map { |row| row.bill.id }
        Agreement.where(id: AgreementBill.where(bill_id: ids, held: true).select(:agreement_id)).proposals.lock.to_a
      end

      def persist(quote, input, today, number)
        tenant = @customer.tenant
        setting = tenant.setting
        segment = quote.segment
        state = quote.pending? ? "pending" : "approved"
        agreement = Agreement.new(
          tenant: tenant, customer: @customer, segment: segment, user: @actor, number: number, state: state, mode: quote.mode, built_on: today,
          valid_until: today + segment.agreement_validity_days, decided_by: (@actor unless quote.pending?), decided_at: (Time.current unless quote.pending?),
          discounts: quote.discounts, base_cents: quote.base_cents, discount_cents: quote.discount_cents, value_cents: quote.value_cents, net_cents: quote.net_cents,
          credit_mode: (quote.credit.mode unless quote.credit.none?), credit_cents: (quote.credit.rebate? ? quote.credit.total : 0), credit_down_cents: (quote.credit.down_payment? ? quote.credit.total : 0),
          down_payment_cents: quote.down_payment_cents, down_payment_due: quote.down_payment_on, installments_count: quote.installments.size, installment_day: (input.day.to_i if quote.installments.any?),
          installment_method: quote.method, rate_pct: quote.rate_pct, effective_annual_pct: quote.effective_annual_pct, total_cents: quote.total_cents, interest_cents: quote.interest_cents,
          schedule: quote.schedule.map { |row| { "number" => row.number, "due" => row.due.iso8601, "amount_cents" => row.amount_cents, "interest_cents" => row.interest_cents, "amortization_cents" => row.amortization_cents, "balance_cents" => row.balance_cents } },
          terms: terms_of(quote, setting, segment)
        )
        quote.rows.each do |row|
          agreement.agreement_bills.build(bill: row.bill, contract: row.bill.contract, base: row.base, discount: row.discount, credit: row.credit, value_cents: row.value,
                                          amount_cents: row.bill.amount_cents, paid_cents: row.bill.paid_cents)
        end
        agreement.save!
        AgreementEvent.log!(agreement, "built", user: @actor, data: { "state" => state, "mode" => quote.mode, "value_cents" => quote.value_cents })
        agreement
      end

      # Tudo o que o acordo congela na proposta (R210): as variáveis do segmento, os parâmetros de encargos, o limite de quem montou, as políticas que congelam,
      # a praça e o que a tela avisou. O segmento que vale é o para negociar (R211).
      def terms_of(quote, setting, segment)
        profile = Membership.active.where(user_id: @actor.id, tenant_id: @customer.tenant_id).includes(:profile).first&.profile
        { "segment" => { "id" => segment.id, "name" => segment.name,
                         "caps" => Caps.normalize(segment.agreement_caps), "max_installments" => segment.agreement_max_installments,
                         "min_installment_cents" => segment.agreement_min_installment_cents, "min_down_payment_pct" => segment.agreement_min_down_payment_pct,
                         "down_payment_days" => segment.agreement_down_payment_days, "validity_days" => segment.agreement_validity_days,
                         "tolerance_days" => segment.agreement_tolerance_days, "break_days" => segment.agreement_break_days },
          "parameters" => Parameters.frozen(setting, segment),
          "limit" => limit_of(quote.limit, profile),
          "policies" => Policies.frozen_for(setting),
          "credit" => { "mode" => quote.credit.mode, "distribution" => quote.credit.distribution, "use" => Policies.value(setting, "credit_use"), "entry_policy" => Policies.value(setting, "credit_entry") },
          "index_policies" => { "missing_index" => setting.missing_index_policy, "negative_index" => setting.negative_index_policy, "interest_form" => setting.default_interest_form },
          "square" => { "municipality_id" => quote.square&.id, "name" => quote.square&.name, "state" => quote.square&.state, "holidays" => quote.calendar.extra_dates.map(&:iso8601) },
          "warnings" => quote.warnings }
      end

      def limit_of(limit, profile)
        { "profile" => profile&.name, "caps" => Caps.normalize(limit.caps), "max_installments" => limit.max_installments, "min_down_payment_pct" => limit.min_down_payment_pct,
          "ceiling_discount_cents" => limit.ceiling_discount_cents, "ceiling_value_cents" => limit.ceiling_value_cents }
      end
  end
end
