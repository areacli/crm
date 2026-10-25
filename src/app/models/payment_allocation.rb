# Quanto de um pagamento cobriu cada componente do valor atualizado de um título (09, R226); o estorno grava linhas negativas.
class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :bill

  enum :component, { interest: "interest", fine: "fine", fees: "fees", correction: "correction", principal: "principal" }, validate: true
end
