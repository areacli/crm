module Agreements
  # Aceite registrado (11, R220, R220a, ACD1): por qualquer usuário com "negociar acordos" no credor, como o termo foi apresentado (canal, data e hora), o canal
  # e o momento do aceite, o comprovante opcional e quem aceitou, com o papel dele. Ao registrar, o CRM confere a proposta de novo; qualquer mudança nos títulos
  # recusa o aceite com "monte a proposta de novo". O aceite leva o acordo a "aguardando efetivação" e guarda o termo como estava, sem edição. Depois do aceite, os títulos de acordo
  # são criados, as promessas dos títulos são canceladas (R222), o crédito é consumido (R223) e, pela política, o acordo é efetivado (R225).
  class Acceptance
    Input = Data.define(:presented_channel, :presented_at, :accepted_channel, :accepted_at, :proof, :accepted_by_customer_id)

    MAX_PROOF = 200

    def initialize(actor) = @actor = actor

    # Os clientes que podem aceitar, com o papel (R220a), conforme a política congelada na proposta.
    def self.acceptors(agreement)
      contracts = agreement.agreement_bills.includes(:contract).map(&:contract).uniq
      Parties.acceptors(contracts, agreement.frozen_policy("who_accepts") || "financial_or_holder")
    end

    def call(agreement, input, now: Time.current)
      ApplicationRecord.transaction do
        agreement.lock!
        refuse!(:not_approved) unless agreement.state_approved?
        refuse!(:validity_passed) if agreement.expired_on?(now.to_date)
        term = Term.build(agreement)
        refuse!(:no_term, missing: term["missing"].to_sentence) if term["missing"].any?
        presented_at, accepted_at = check_times(agreement, input, now)
        customer, role = check_acceptor(agreement, input)
        recheck!(agreement, now.to_date)
        recheck_credit!(agreement)
        agreement.update!(state: "awaiting_effectuation", presented_channel: input.presented_channel, presented_at: presented_at, accepted_channel: input.accepted_channel,
                          accepted_at: accepted_at, proof: input.proof.to_s.strip.presence, accepted_by_customer: customer, accepted_role: role, registered_by: @actor,
                          registered_at: now, term_snapshot: term.merge("accepted_by" => { "name" => customer.name, "role" => role }, "accepted_at" => accepted_at.iso8601, "presented_at" => presented_at.iso8601))
        AgreementEvent.log!(agreement, "accepted", user: @actor, data: { "channel" => input.accepted_channel, "customer_id" => customer.id, "role" => role })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "accepted", before: "approved", after: "awaiting_effectuation")
        finish!(agreement, accepted_at)
      end
      agreement
    end

    private
      # Depois do aceite (R221 a R225): consome o crédito, cria os títulos de acordo, cancela as promessas dos títulos, paga a entrada com o crédito e efetiva pelo aceite.
      def finish!(agreement, accepted_at)
        CreditUse.consume!(agreement, @actor, accepted_at)
        Titles.build!(agreement)
        PromiseCancellation.call(agreement, @actor)
        entry = agreement.entry_title
        if CreditUse.pay_down_payment!(agreement, entry, accepted_at)
          remaining = LedgerLoader.new(agreement.tenant, today: accepted_at.to_date).one(entry.reload).due(accepted_at.to_date).total
          covered = remaining.zero? || (agreement.minimum_cents.positive? && remaining <= agreement.minimum_cents)
          Effectuation.call(agreement, by: "credit", at: accepted_at, actor: @actor) if covered
        end
        Effectuation.call(agreement, by: "acceptance", at: accepted_at, actor: @actor) if Effectuation.by_acceptance?(agreement)
        Standing.refresh!(agreement, today: accepted_at.to_date) if agreement.effectuated?
      end

      # R220 (S4): o crédito usado que deixou de estar disponível, ou a mudança de "uso do crédito" ou de "como o crédito entra" numa proposta que usa crédito, recusa o aceite.
      def recheck_credit!(agreement)
        return unless agreement.credit_mode.present?

        refuse!(:credit_unavailable) if CreditUse.unavailable(agreement)
        setting = agreement.tenant.setting
        changed = Policies.value(setting, "credit_use") != agreement.terms.dig("credit", "use") || Policies.value(setting, "credit_entry") != agreement.terms.dig("credit", "entry_policy")
        refuse!(:credit_policy_changed) if changed
      end

      # R220: a apresentação e o aceite são posteriores à aprovação; a apresentação não é posterior ao aceite; o aceite está entre a montagem e o registro.
      def check_times(agreement, input, now)
        refuse!(:channel) unless Agreement::CHANNELS.include?(input.presented_channel) && Agreement::CHANNELS.include?(input.accepted_channel)
        presented_at = input.presented_at or refuse!(:presented_time)
        accepted_at = input.accepted_at or refuse!(:accepted_time)
        approved_at = agreement.decided_at || agreement.created_at
        refuse!(:accepted_future) if accepted_at > now
        refuse!(:presented_after_accepted) if presented_at > accepted_at
        refuse!(:before_approval) if presented_at < approved_at || accepted_at < approved_at
        refuse!(:before_built) if accepted_at < agreement.created_at
        refuse!(:proof_too_long, max: MAX_PROOF) if input.proof.to_s.length > MAX_PROOF
        [ presented_at, accepted_at ]
      end

      # R220a: aceita o responsável financeiro ou um titular dos contratos dos títulos, conforme a política congelada.
      def check_acceptor(agreement, input)
        options = self.class.acceptors(agreement)
        found = options.find { |customer, _| customer.id == input.accepted_by_customer_id.to_i }
        return found if found

        any = ContractCustomer.exists?(contract_id: agreement.agreement_bills.select(:contract_id), customer_id: input.accepted_by_customer_id.to_i)
        refuse!(any ? :acceptor_not_allowed : :acceptor_unknown)
      end

      # R220: confere de novo a proposta; qualquer mudança recusa o aceite. O valor atualizado mudar com os dias não recusa.
      def recheck!(agreement, today)
        agreement.agreement_bills.includes(:bill).each do |item|
          bill = item.bill
          refuse!(:bill_left, number: bill.number) unless bill.active?
          refuse!(:bill_value_changed, number: bill.number) if bill.amount_cents != item.amount_cents
          refuse!(:bill_paid, number: bill.number) if bill.paid_cents != item.paid_cents || Payment.where(bill_id: bill.id).where("created_at > ?", agreement.created_at).exists?
          refuse!(:bill_reversed, number: bill.number) if PaymentReversal.joins(:payment).where(payments: { bill_id: bill.id }).where("payment_reversals.created_at > ?", agreement.created_at).exists?
        end
        refuse!(:down_overdue) if agreement.down_payment_due < today
      end

      def refuse!(key, **options) = raise(Refused, I18n.t("agreements.accept_refused.#{key}", **options))
  end
end
