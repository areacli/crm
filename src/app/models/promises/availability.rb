module Promises
  # Títulos que o contrato oferece a uma promessa nova (R183, R185, R188): em aberto, fora de promessa pendente ou aberta e fora da carência. Os que
  # não entram aparecem com o motivo ("em promessa de Pedro"), porque o operador precisa saber por que o título não está na lista.
  class Availability
    Entry = Data.define(:bill, :blocked) # blocked: nil ou o texto do motivo

    def initialize(contract, today: Date.current)
      @contract = contract
      @today = today
    end

    def entries
      @entries ||= begin
        bills = @contract.bills.active.kind_common.where("amount_cents > paid_cents").order(:due_date, :id).to_a
        reasons = blocked_reasons(bills.map(&:id))
        bills.map { |bill| Entry.new(bill, reasons[bill.id]) }
      end
    end

    def free = entries.select { |entry| entry.blocked.nil? }.map(&:bill)

    private
      def blocked_reasons(bill_ids)
        return {} if bill_ids.empty?

        reasons = {}
        PaymentPromiseBill.where(bill_id: bill_ids, held: true).includes(promise: :customer).each do |row|
          reasons[row.bill_id] = I18n.t("promises.blocked.in_promise", name: row.promise.customer.name)
        end
        # 11, R183, R218: título em proposta de acordo, ou preso a acordo aceito que não terminou, não entra em promessa nova.
        AgreementBill.where(bill_id: bill_ids, held: true).includes(:agreement).each do |row|
          reasons[row.bill_id] = I18n.t("promises.blocked.in_agreement", number: row.agreement.number)
        end
        grace_days = @contract.tenant.setting.promise_grace_days
        return reasons unless grace_days.positive?

        # R188: a carência conta do dia em que a promessa quebrou, foi cancelada, recusada ou não aprovada, qualquer que seja o cliente que prometeu.
        PaymentPromiseBill.joins(:promise).where(bill_id: bill_ids, removed_at: nil, payment_promises: { state: PaymentPromise::GRACE_STATES })
                          .where.not(bill_id: reasons.keys).where(payment_promises: { grace_free: false }).where("payment_promises.closed_at > ?", @today.beginning_of_day - grace_days.days)
                          .select("payment_promise_bills.bill_id", "payment_promises.closed_at").each do |row|
          until_date = row.closed_at.to_date + grace_days.days
          reasons[row.bill_id] = I18n.t("promises.blocked.grace", date: I18n.l(until_date, format: "%d/%m/%Y")) if until_date > @today
        end
        reasons
      end
  end
end
