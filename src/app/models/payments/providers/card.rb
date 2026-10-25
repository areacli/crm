module Payments
  module Providers
    # Contrato de cartão (12, R258): só por checkout transparente (R278). O navegador do pagador tokeniza o cartão com a biblioteca do
    # fornecedor e o servidor recebe só o `payment_token`; dado de cartão nunca passa por aqui.
    #
    # Além das operações, o adaptador de cartão declara no manifesto (`capabilities[:card_checkout]`) o que a página pública precisa: o módulo
    # JavaScript da biblioteca do fornecedor (`script`, fixado no repositório, com o SHA-256 e a versão), o módulo que a usa (`driver`) e os
    # domínios que a política de segurança de conteúdo da página libera (`hosts`: script, connect, frame, img). Os valores públicos de cada conta
    # (por exemplo, o identificador da conta e o ambiente) saem de `card_checkout_config`.
    module Card
      # Opções de parcelamento para o valor (e a bandeira, quando o fornecedor calcula por bandeira): Array de InstallmentOption.
      def installments(account, amount_cents:, brand: nil) = not_implemented(:card, __method__)

      # Cobra com o token da biblioteca do fornecedor. `payer`: { name:, document:, address:, email:, phone: }. Devolve CardResult.
      def charge_card(account, custom_id:, amount_cents:, installments:, payment_token:, payer:, description: nil, notification_url: nil) = not_implemented(:card, __method__)

      def fetch_card(account, external_id) = not_implemented(:card, __method__)

      # Devolve o valor (parcial ou total) de uma cobrança de cartão paga.
      def refund_card(account, external_id, amount_cents:) = not_implemented(:card, __method__)

      # Valores públicos que o JavaScript da página usa com a biblioteca (nunca segredo).
      def card_checkout_config(account) = {}

      # Domínios que a política de segurança de conteúdo da página libera para a biblioteca do fornecedor: { script: [], connect: [], frame: [], img: [] }
      # (origens com esquema, como "https://exemplo.com.br"). A página libera estes e mais nada.
      def card_checkout_hosts(account) = { script: [], connect: [], frame: [], img: [] }
    end
  end
end
