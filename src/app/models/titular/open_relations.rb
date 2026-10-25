module Titular
  # O que impede anonimizar um cliente (07, R130, R130a): olha todos os contratos em que ele figura, inclusive os títulos e o crédito
  # dos outros clientes do mesmo contrato, e nunca identifica esses outros. Acordos e promessas entram com os incrementos 10 e 11.
  class OpenRelations
    Item = Data.define(:kind, :contract, :cents)

    def initialize(customer) = @customer = customer

    def items
      @items ||= contract_items + pending_items
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

      # Pagamento pendente com o documento do cliente (sem título ainda), mesmo de outro contrato: vale o que ainda não foi estornado.
      def pending_items
        cents = Payment.where(tenant_id: @customer.tenant_id, status: "pending", document: @customer.document).sum("amount_cents - reversed_cents")
        cents.positive? ? [ Item.new("pending", nil, cents) ] : []
      end
  end
end
