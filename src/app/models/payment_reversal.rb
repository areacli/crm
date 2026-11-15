# Estorno de pagamento (R60 a R64): guarda de onde saiu o valor, do crédito que o pagamento gerou ou do título. Identificado, como o pagamento,
# por credor, fornecedor, conta e identificador (R61; 03, revisão 12); o meio, o fornecedor e a conta são os do pagamento estornado.
class PaymentReversal < ApplicationRecord
  include TenantScoped

  belongs_to :payment

  before_validation -> { self.payment_method ||= payment&.payment_method; self.provider ||= payment&.provider; self.account_key ||= payment&.account_key }
  belongs_to :import, optional: true
end
