module Titular
  # O que impede anonimizar um cliente (07, R130, R130a): olha todos os contratos em que ele figura, inclusive os títulos e o crédito
  # dos outros clientes do mesmo contrato, e nunca identifica esses outros. A promessa aberta ou pendente (10) e o acordo aguardando efetivação, ativo ou quebrado com título em
  # cobrança (11, R247) também são relação em aberto; o acordo encerrado não é.
  class OpenRelations
    Item = Data.define(:kind, :contract, :cents)

    def initialize(customer) = @customer = customer

    def items
      @items ||= contract_items + pending_items + promise_items + agreement_items
    end

    def any? = items.any?

    # Frase única para a recusa: "contrato C-1 com título em aberto de R$ 300,00; crédito do contrato C-1 de R$ 80,00".
    def message
      items.map { |item| I18n.t("titular.open.#{item.kind}", contract: item.contract, value: Money.format(item.cents)) }.to_sentence(words_connector: "; ", two_words_connector: "; ", last_word_connector: "; ")
    end

    private
      def contract_items
        ids = @customer.contract_ids
        return [] if ids.empty?

        rows = Portfolio::Sql.rows("with #{Facts.sql(contract_ids: ids)} select * from facts where open order by contract_id")
        rows.flat_map do |row|
          label = row["code"].presence || I18n.t("titular.open.no_code")
          [ (Item.new("active", label, row["active_cents"].to_i) if row["active_count"].to_i.positive?),
            (Item.new("withdrawn", label, row["withdrawn_cents"].to_i) if row["withdrawn_cents"].to_i.positive?),
            (Item.new("credit", label, row["credit_cents"].to_i) if row["credit_cents"].to_i.positive?) ].compact
        end
      end

      # Promessa aberta ou pendente do cliente (10).
      def promise_items
        PaymentPromise.where(customer_id: @customer.id, state: PaymentPromise::HOLDING).includes(:contract).map { |promise| Item.new("promise", promise.number.presence || promise.contract.label, promise.total_cents) }
      end

      # Acordo aguardando efetivação, ativo ou quebrado com título em cobrança, e estorno à espera do gestor (11, R247, R233).
      def agreement_items
        running = Agreement.where(customer_id: @customer.id, state: %w[awaiting_effectuation active_on_time active_late]).to_a +
                  Agreement.where(customer_id: @customer.id, state: "broken").select { |agreement| agreement.titles.where(status: "active").exists? }
        items = running.map { |agreement| Item.new("agreement", agreement.number, agreement.value_cents) }
        waiting = ReversalWait.where(tenant_id: @customer.tenant_id, state: "waiting", agreement_id: Agreement.where(customer_id: @customer.id).select(:id)).sum(:amount_cents)
        waiting.positive? ? items + [ Item.new("reversal_wait", nil, waiting) ] : items
      end

      # Pagamento pendente com o documento do cliente (sem título ainda), mesmo de outro contrato: vale o que ainda não foi estornado.
      def pending_items
        cents = Payment.where(tenant_id: @customer.tenant_id, status: "pending", document: @customer.document).sum("amount_cents - reversed_cents")
        cents.positive? ? [ Item.new("pending", nil, cents) ] : []
      end
  end
end
