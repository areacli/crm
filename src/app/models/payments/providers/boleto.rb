module Payments
  module Providers
    # Contrato de boleto (12, R258). `payer`: Hash com name, document e endereço (o que o fornecedor exige); `custom_id`: nosso identificador de
    # idempotência. Todas as operações devolvem `Issued` (ou levantam `Payments::Providers::Error`). O adaptador que não implementa uma
    # operação herda a que levanta `NotImplementedError`.
    module Boleto
      def issue_boleto(account, custom_id:, amount_cents:, due_on:, payer:, options: {}) = not_implemented(:boleto, __method__)

      def fetch_boleto(account, external_id) = not_implemented(:boleto, __method__)

      def cancel_boleto(account, external_id) = not_implemented(:boleto, __method__)

      def change_boleto_due_date(account, external_id, due_on) = not_implemented(:boleto, __method__)

      # O PDF (ficha de compensação) do boleto, em bytes, baixado pelo servidor (R273): nunca se manda o usuário ao link do fornecedor. O padrão
      # usa o que a consulta devolve; o adaptador cujo PDF vem de outro lugar (Efí) sobrescreve.
      def download_boleto_pdf(account, external_id) = fetch_boleto(account, external_id).pdf
    end
  end
end
