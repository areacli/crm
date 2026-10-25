# Quanto de um pagamento cobriu cada componente do valor atualizado de um título (09, R226); o estorno grava linhas negativas.
class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :bill

  # `late` (encargos de atraso) e `installment_interest` (juros do parcelamento) são dos títulos de acordo (11, R227).
  enum :component, { interest: "interest", fine: "fine", fees: "fees", correction: "correction", principal: "principal", late: "late", installment_interest: "installment_interest",
                       inherited_installment_interest: "inherited_installment_interest", inherited_late: "inherited_late" }, validate: true
end
