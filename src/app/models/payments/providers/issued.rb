module Payments
  module Providers
    # Resposta normalizada de uma emissão ou consulta (vocabulário nosso). `status`: active, paid, expired, canceled ou failed.
    # `paid_cents` e `refunded_cents` (parte D): o que a consulta diz ter sido pago e devolvido, quando o fornecedor informa (nil = não informa).
    # `pdf` e `qr_png` são o conteúdo binário (ou nil, quando o fornecedor só dá texto: o QR Code é então gerado aqui).
    Issued = Data.define(:external_id, :status, :amount_cents, :due_on, :digitable_line, :copy_paste, :pdf, :qr_png, :paid_cents, :refunded_cents) do
      def initialize(external_id:, status:, amount_cents:, due_on: nil, digitable_line: nil, copy_paste: nil, pdf: nil, qr_png: nil, paid_cents: nil, refunded_cents: nil)
        super
      end
    end
  end
end
