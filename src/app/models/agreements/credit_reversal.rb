module Agreements
  # O estorno da origem de um crédito que o acordo usou (11, R233, U1, V1, AE5): o que o CRM faz depende de como o crédito entrou e de em que pé está o acordo.
  # - acordo aguardando efetivação, crédito como abatimento: o acordo é cancelado com "crédito estornado: monte a proposta de novo" (V1);
  # - acordo aguardando efetivação, crédito como pagamento da entrada: a entrada volta a aberto pela parte estornada, e o acordo segue (AE5);
  # - depois da efetivação, crédito como abatimento: nasce o **título de estorno** pelo valor estornado, com a composição que o crédito tinha coberto nos originais (U1, padrão), ou a
  #   entrada volta a aberta por esse valor (alternativa da U1, que o termo aceito prevê);
  # - crédito como pagamento da entrada: o título reabre pela parte, pela regra base, e essa parte nunca é abatida por mínimo.
  # Acordo cancelado ou que nunca foi aceito: o crédito já voltou disponível; o estorno fica à espera do gestor.
  class CreditReversal
    REASON = "crédito estornado: monte a proposta de novo".freeze

    def initialize(import, effects)
      @import = import
      @effects = effects
    end

    def call(entry, cents, row)
      agreement = Agreement.find(entry.agreement_id)
      on = Date.iso8601(row["reversed_on"].to_s)
      return @effects.wait_credit(row, cents) unless Agreement::RUNNING.include?(agreement.state) || %w[settled renegotiated].include?(agreement.state)

      if agreement.credit_mode == "down_payment"
        reopen_down_payment(agreement, cents, on)
      elsif agreement.state_awaiting_effectuation?
        @effects.request_cancel(agreement.id, REASON)
      elsif agreement.frozen_policy("credit_reversal_origin") == "reopen_down_payment"
        reopen_entry(agreement, cents, on)
      else
        reversal_title(agreement, cents, on)
      end
    end

    private
      # Crédito usado como pagamento da entrada: a entrada reabre pela parte (o pagamento do canal de crédito é desfeito do último componente para o primeiro).
      def reopen_down_payment(agreement, cents, on)
        entry = agreement.entry_title or return @effects.wait_credit({}, cents)
        channel = PaymentChannel.find_by(tenant_id: agreement.tenant_id, code: CreditUse::CHANNEL_CODE)
        left = cents
        Payment.where(agreement_id: agreement.id, channel_id: channel&.id).order(id: :desc).each do |payment|
          break unless left.positive?

          left -= AllocationUndo.call(payment, entry.reload, cents: left).cash
        end
        entry.update!(composition: entry.composition.merge("no_minimum" => true))
        @effects.note_reopened(entry.id, agreement.id, on)
      end

      # U1, alternativa: a entrada volta a aberta pelo valor estornado, com a composição que o crédito cobrira (a face da entrada cresce).
      def reopen_entry(agreement, cents, on)
        entry = agreement.entry_title or return
        items = pieces(agreement, cents)
        entry.update!(amount_cents: entry.amount_cents + items.sum { |item| item["cents"] }, status: "active", paid_on: nil,
                      composition: entry.composition.merge("items" => entry.composition["items"] + items, "no_minimum" => true))
        @effects.note_reopened(entry.id, agreement.id, on)
      end

      # U1, padrão: o título de estorno pelo valor estornado, com a composição que o crédito tinha coberto nos originais.
      def reversal_title(agreement, cents, on)
        items = pieces(agreement, cents)
        return if items.empty?

        contract = agreement.agreement_bills.includes(:bill).min_by { |item| [ item.bill.due_date, item.bill_id ] }.contract
        title = ReversalTitles.create!(agreement, items: items, contract: contract, action_on: on, processed_on: Date.current, reason: "u1")
        title.update!(composition: title.composition.merge("credit_origin" => items.sum { |item| item["cents"] }))
        @effects.touch_agreement(agreement.id)
      end

      # A composição que o crédito cobriu, tirada na ordem inversa da alocação (principal primeiro, do título mais novo para o mais antigo), sem repetir o que um estorno anterior já tirou.
      def pieces(agreement, cents)
        reversed = agreement.terms.fetch("credit_reversed", {}).dup
        items = []
        agreement.agreement_bills.includes(:bill).sort_by { |item| [ item.bill.due_date, item.bill_id ] }.reverse_each do |item|
          Agreements::BASE_ORDER.reverse_each do |component|
            break unless cents.positive?

            key = "#{item.bill_id}:#{component}"
            have = item.credit.fetch(component, 0) - reversed.fetch(key, 0)
            part = [ cents, have ].min
            next unless part.positive?

            items << { "bill_id" => item.bill_id, "component" => component, "cents" => part }
            reversed[key] = reversed.fetch(key, 0) + part
            cents -= part
          end
        end
        agreement.update!(terms: agreement.terms.merge("credit_reversed" => reversed))
        items.sort_by { |item| [ Agreements::BASE_ORDER.index(item["component"]) ] }
      end
  end
end
