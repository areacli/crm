module Promises
  # Valor da promessa (R186, DP10): cada título com o principal e todos os encargos calculados para a data prometida, pela regra do segmento do
  # contrato (09). Título que vence depois da data entra pelo saldo. É o mesmo motor da baixa (Charges::Settlement); não há código de cálculo novo.
  module Pricing
    Row = Data.define(:bill, :components) do
      def total_cents = components.values.sum
    end
    Quote = Data.define(:rows, :promised_on) do
      def total_cents = rows.sum(&:total_cents)
    end

    module_function

    def quote(tenant, bills, promised_on)
      # O motor lê os títulos vencidos até a data prometida e as tabelas de índice até ela.
      settlement = Charges::Settlement.for(tenant, today: promised_on)
      settlement&.preload(bills.map(&:id))
      rows = bills.map do |bill|
        balance = bill.balance_cents
        Row.new(bill, settlement&.due(bill.id, promised_on, balance) || { "principal" => balance })
      end
      Quote.new(rows, promised_on)
    end
  end
end
