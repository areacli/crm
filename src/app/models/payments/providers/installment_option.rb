module Payments
  module Providers
    # Opção de parcelamento: o número de parcelas, o valor de cada uma e o total (com juros, se houver).
    InstallmentOption = Data.define(:installments, :installment_cents, :total_cents, :has_interest)
  end
end
