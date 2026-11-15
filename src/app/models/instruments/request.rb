module Instruments
  # O ponto único da emissão (16; plano técnico da camada 20, parte B), no que a régua precisa (plano técnico da camada 23, decisão 6): os objetos
  # que aceitam instrumento (R376), o meio da promessa (R377), um vigente por objeto e meio (R378, com o "reemitir" da R385), o valor e o vencimento
  # do objeto (R379) e o pagador (R381). A emissão na ficha, no registro e em lote sobre um segmento continuam com a camada 20.
  #
  # Pareto desta parte, registrado no plano: o título de acordo usa o saldo do título; a multa e os juros depois do vencimento (R380) vão como a
  # integração já manda; o link de cartão não sai pela régua.
  class Request
    Result = Data.define(:issued, :refusals) do
      def reason = refusals.first || I18n.t("instruments.request.nothing")

      def detail
        names = issued.map { |instrument| "#{instrument.kind.upcase}-#{instrument.id}" }
        I18n.t("instruments.request.issued", count: issued.size, kind: I18n.t("payments.accounts.modalities.#{issued.first.kind}"), names: names.join(", "))
      end
    end

    # A ação "emitir instrumento" de uma decisão da régua (21, R433, R447).
    def self.for_cadence(decision, action, today: Date.current) = new(decision.cadence.tenant, today).for_cadence(decision, action)

    def initialize(tenant, today)
      @tenant = tenant
      @today = today
      @issuer = Payments::Issuer.new
    end

    def for_cadence(decision, action)
      kind = PaymentMethod::ISSUABLE[action.payment_method]
      objects = objects_of(decision, action.params["object"])
      return Result.new(issued: [], refusals: [ I18n.t("instruments.request.no_object.#{action.params['object']}") ]) if objects.empty?

      issued = []
      refusals = []
      objects.each do |object|
        outcome = issue(object, kind, action, decision)
        outcome.is_a?(PaymentInstrument) ? issued << outcome : refusals << outcome
      end
      Result.new(issued: issued, refusals: refusals)
    end

    private
      def objects_of(decision, object)
        contracts = decision.contract_id ? [ decision.contract_id ] : ContractCustomer.where(customer_id: decision.customer_id).pluck(:contract_id)
        case object
        when "bill" then [ decision.bill ].compact
        when "overdue_bills" then Bill.where(contract_id: contracts, status: "active", kind: "common").where(due_date: ...@today).order(:due_date, :id).to_a
        when "agreement_bills" then Bill.where(contract_id: contracts, status: "active").of_agreement.order(:due_date, :id).to_a
        when "promise" then PaymentPromise.where(contract_id: contracts, state: "open").where(promised_on: @today..).order(:promised_on, :id).to_a
        else []
        end
      end

      # Devolve o instrumento emitido, ou o motivo da recusa.
      def issue(object, kind, action, decision)
        refusal = ineligible(object, action)
        return refusal if refusal

        current = PaymentInstrument.find_by(tenant_id: @tenant.id, kind: kind, open: true, **object_key(object))
        if current
          return I18n.t("instruments.request.already_active", kind: I18n.t("payments.accounts.modalities.#{kind}")) unless action.params["reissue"]

          @issuer.cancel(current)
        end
        amount, due_on = price(object, action)
        return I18n.t("instruments.request.zero") unless amount.positive?

        instrument = @issuer.issue_now(tenant: @tenant, kind: kind, amount_cents: amount, customer: payer(object), object: object, due_on: due_on,
                                       custom_id: custom_id(decision, object), origin: "rule", object_snapshot: snapshot(object, amount, due_on))
        instrument.state_active? ? instrument : (instrument.failure_reason.presence || I18n.t("instruments.request.failed"))
      rescue Payments::Issuer::Refused, Payments::Providers::Error => error
        error.message
      end

      # R376 e R377.
      def ineligible(object, action)
        if object.is_a?(PaymentPromise)
          return I18n.t("instruments.request.promise_closed") unless object.state_open? && object.promised_on >= @today
          return I18n.t("instruments.request.promise_method", method: PaymentMethod.label(object.payment_method)) if object.payment_method != action.payment_method
        elsif !object.active?
          return I18n.t("instruments.request.bill_closed")
        end
        nil
      end

      # R379: fatura e título vencidos pelo saldo atualizado para o vencimento escolhido; a vencer, no vencimento dele; promessa, o que falta, na data.
      def price(object, action)
        return [ object.total_cents - object.paid_cents, object.promised_on ] if object.is_a?(PaymentPromise)

        overdue = object.due_date < @today
        due_on = overdue ? @today + action.params["due_days"].to_i : object.due_date
        balance = object.balance_cents
        return [ balance, due_on ] unless overdue && object.kind_common?

        settlement = Charges::Settlement.for(@tenant, today: @today)
        settlement&.preload([ object.id ])
        components = settlement&.due(object.id, due_on, balance)
        [ components ? components.values.sum : balance, due_on ]
      end

      # R381: a promessa, quem prometeu; o título de acordo, quem aceitou; a fatura, o responsável financeiro do contrato, senão o titular.
      def payer(object)
        return object.customer if object.is_a?(PaymentPromise)
        return object.agreement.try(:accepted_by_customer) || object.customer if object.agreement

        links = ContractCustomer.where(contract_id: object.contract_id).includes(:customer).to_a
        (links.find { |link| Array(link.roles).include?("financial_responsible") } || links.find { |link| Array(link.roles).include?("holder") || link.roles.blank? })&.customer ||
          object.customer
      end

      def object_key(object) = object.is_a?(PaymentPromise) ? { promise_id: object.id } : { bill_id: object.id }

      # O mesmo pedido da régua devolve o mesmo instrumento (R272): decisão e objeto.
      def custom_id(decision, object) = format("rgd%012d%s%012d", decision.id, object.is_a?(PaymentPromise) ? "P" : "B", object.id)

      def snapshot(object, amount, due_on) = { "amount_cents" => amount, "due_on" => due_on.iso8601, "origin" => "rule" }
  end
end
