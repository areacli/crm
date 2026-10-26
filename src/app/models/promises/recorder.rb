module Promises
  # Registro da promessa junto do acionamento (R183 a R193): títulos de um contrato só, meio, data prometida; alçada decide se nasce aberta ou pendente;
  # valor calculado para a data prometida e congelado. Roda dentro da transação do acionamento (04), então, se a promessa for recusada, nada é gravado.
  class Recorder
    FIELDS = %i[promise_contract_id promise_bill_ids promise_payment_method promise_on].freeze

    def initialize(actor) = @actor = actor

    # A promessa foi pedida quando o formulário traz algum dos campos dela preenchido.
    def self.requested?(attributes)
      Array(attributes[:promise_bill_ids]).any?(&:present?) || attributes[:promise_payment_method].present? || attributes[:promise_on].present?
    end

    # `attempt` já está gravado; devolve a promessa criada.
    def register(attempt, customer, result, attributes)
      refuse!(:result_not_allowed) unless result.allows_promise?
      contract = contract_for(attempt, customer, attributes)
      bills = chosen_bills(contract, attributes[:promise_bill_ids])
      method = attributes[:promise_payment_method].to_s
      refuse!(:method) unless Payment.payment_methods.key?(method)
      contacted_on = attempt.contacted_at.in_time_zone.to_date
      segment = Limits.segment_of(contract)
      promised_on = check_date(attributes[:promise_on], contacted_on, segment)

      state = (promised_on - contacted_on).to_i <= Limits.days_for(@actor, attempt.tenant_id, segment) ? "open" : "pending"
      quote = Pricing.quote(contract.tenant, bills, promised_on)
      setting = contract.tenant.setting
      promise = PaymentPromise.create!(
        tenant_id: attempt.tenant_id, customer: customer, contract: contract, contact_attempt: attempt, user: @actor, segment: segment, state: state,
        number: (Numbering.next_for(attempt.tenant_id) if state == "open"), payment_method: method, promised_on: promised_on, contacted_on: contacted_on,
        total_cents: quote.total_cents, decided_at: (Time.current if state == "open"), policies: policies_of(setting, segment, Limits.days_for(@actor, attempt.tenant_id, segment))
      )
      quote.rows.each { |row| promise.promise_bills.create!(row_attributes(row)) }
      Change.record!(tenant_id: promise.tenant_id, user: @actor, subject_type: "payment_promise", subject_id: promise.id, event: "created", after: state)
      promise
    rescue ActiveRecord::RecordNotUnique
      # R185 no banco: dois registros ao mesmo tempo sobre o mesmo título; o segundo é recusado.
      refuse!(:bill_taken)
    end

    private
      # O contrato vem do acionamento, se informado (R69b); senão, do campo da promessa. O cliente precisa figurar nele (R183a).
      def contract_for(attempt, customer, attributes)
        informed = attributes[:promise_contract_id].presence
        refuse!(:contract_differs) if attempt.contract_id && informed && informed.to_s != attempt.contract_id.to_s
        contract = attempt.contract || (informed && Contract.find_by(id: informed, tenant_id: customer.tenant_id))
        refuse!(:contract_required) unless contract
        refuse!(:customer_not_in_contract) unless ContractCustomer.exists?(contract_id: contract.id, customer_id: customer.id)
        contract
      end

      # R183, R183b, R185, R188: de 1 a n títulos do contrato, em aberto, que nenhuma promessa prende e fora da carência.
      def chosen_bills(contract, raw_ids)
        ids = Array(raw_ids).filter_map { |id| id.presence&.to_i }.uniq
        refuse!(:bills_required) if ids.empty?
        bills = Bill.where(id: ids, tenant_id: contract.tenant_id).to_a
        refuse!(:bill_unknown) if bills.size != ids.size
        refuse!(:one_contract) if bills.any? { |bill| bill.contract_id != contract.id }

        entries = Availability.new(contract).entries.index_by { |entry| entry.bill.id }
        bills.each do |bill|
          entry = entries[bill.id]
          refuse!(:bill_not_open, number: bill.number) unless entry
          raise Refused, I18n.t("promises.refused.bill_blocked", number: bill.number, reason: entry.blocked) if entry.blocked
        end
        bills.sort_by { |bill| [ bill.due_date, bill.id ] }
      end

      # R189, R191: a data não passa do prazo máximo do segmento, nem com aprovação, e não é anterior ao dia do contato.
      def check_date(raw, contacted_on, segment)
        date = parse_date(raw) or refuse!(:date_invalid)
        refuse!(:date_before_contact) if date < contacted_on
        limit = contacted_on + Limits.ceiling(segment).days
        raise Refused, I18n.t("promises.refused.date_too_far", date: I18n.l(limit, format: "%d/%m/%Y")) if date > limit

        date
      end

      def parse_date(raw)
        return if raw.blank?

        Date.iso8601(raw.to_s)
      rescue Date::Error
        BrDate.parse(raw.to_s)
      end

      # R187: as políticas e a alçada do momento ficam congeladas na promessa; mudar a política vale só para as promessas novas.
      def policies_of(setting, segment, limit_days)
        { "tolerance_days" => setting.promise_tolerance_days, "counting" => setting.promise_counting, "min_paid_pct" => setting.promise_min_paid_pct,
          "after_break" => setting.promise_after_break, "grace_days" => setting.promise_grace_days, "partial" => setting.promise_partial,
          "limit_days" => limit_days, "ceiling_days" => segment.promise_max_days }
      end

      def row_attributes(row)
        components = row.components
        { bill_id: row.bill.id, principal_cents: components.fetch("principal", 0), correction_cents: components.fetch("correction", 0), fine_cents: components.fetch("fine", 0),
          interest_cents: components.fetch("interest", 0), fees_cents: components.fetch("fees", 0), total_cents: row.total_cents }
      end

      def refuse!(key, **options) = raise(Refused, I18n.t("promises.refused.#{key}", **options))
  end
end
