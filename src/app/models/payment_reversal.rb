# Estorno de pagamento (R60 a R64): guarda de onde saiu o valor, do crédito que o pagamento gerou ou do título.
class PaymentReversal < ApplicationRecord
  include TenantScoped

  belongs_to :channel, class_name: "PaymentChannel"
  belongs_to :payment
  belongs_to :import, optional: true
end
