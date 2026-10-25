module Payments
  module Providers
    # Contrato de Pix (12, R258): cobrança com vencimento (IP-1). Devolve `Issued` com o "copia e cola" e, se o fornecedor der, a imagem do QR Code.
    module Pix
      def issue_pix(account, custom_id:, amount_cents:, due_on:, payer:, options: {}) = not_implemented(:pix, __method__)

      def fetch_pix(account, external_id) = not_implemented(:pix, __method__)

      def cancel_pix(account, external_id) = not_implemented(:pix, __method__)

      # Devolve o valor (parcial ou total) de um Pix pago. `refund_id` (nosso, opcional) torna a devolução idempotente; o fornecedor avisa o resultado (parte D).
      def refund_pix(account, external_id, amount_cents:, refund_id: nil) = not_implemented(:pix, __method__)
    end
  end
end
