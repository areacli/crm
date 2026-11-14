module Payments
  # Cadastro do endereço do nosso webhook no fornecedor (12, revisão 4, R284g). É operação, nunca tela: depende do certificado que o fornecedor exige do
  # nosso servidor (pré-requisito O1 do plano do Bradesco). Chama o adaptador e grava na integração quando foi feito e para que endereço (o detalhe da
  # integração mostra a data). O endereço guardado leva o `hmac`, que não é segredo (é derivado do segredo e já vai ao fornecedor).
  class WebhookRegistration
    def initialize(account) = @account = account

    def call(now: Time.current)
      raise Providers::Error, I18n.t("payments.instruments.account_unavailable") unless @account.active? && @account.provider_available?

      url = @account.adapter.register_webhook(@account)
      raise Providers::Error, I18n.t("payments.webhook_registration.too_long", max: WebhookUrl::MAX_URL) if url.to_s.length > 300

      @account.update_columns(webhook_registered_at: now, webhook_registered_url: url.to_s)
      url
    end
  end
end
