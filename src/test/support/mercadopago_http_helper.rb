# O Mercado Pago nos testes (12, revisão 6): o cliente HTTP falso da Efí, com respostas gravadas à mão a partir dos exemplos da documentação, e a aplicação da
# instalação (OAuth e o segredo do webhook) pelas variáveis de ambiente de teste. Nenhum teste chama o Mercado Pago.
module MercadopagoHttpHelper
  ORDER_ID = "ORD01JQ4S4KY8HWQ6NA5PXB65B3D3".freeze
  PAYMENT_ID = "PAY01JQ4S4KY8HWQ6NA5PXB65B3D4".freeze
  SELLER = "123456789".freeze
  APP_ENV = { "CRM_CONNECT_MERCADOPAGO_SANDBOX_CLIENT_ID" => "app-mp-sandbox", "CRM_CONNECT_MERCADOPAGO_SANDBOX_CLIENT_SECRET" => "segredo-mp-sandbox",
              "CRM_CONNECT_MERCADOPAGO_SANDBOX_WEBHOOK_SECRET" => "segredo-webhook-sandbox", "CRM_CONNECT_MERCADOPAGO_PRODUCTION_CLIENT_ID" => "app-mp",
              "CRM_CONNECT_MERCADOPAGO_PRODUCTION_CLIENT_SECRET" => "segredo-mp", "CRM_CONNECT_MERCADOPAGO_PRODUCTION_WEBHOOK_SECRET" => "segredo-webhook" }.freeze

  def use_mercadopago_client(client)
    Payments::Providers::Mercadopago.http_client = client
    client
  end

  def mercadopago_client = EfiHttpHelper::FakeClient.new

  def with_mercadopago_app = APP_ENV.each { |key, value| ENV[key] = value }

  def without_mercadopago_app = APP_ENV.each_key { |key| ENV.delete(key) }

  # Integração Mercado Pago conectada à conta SELLER, com a Public Key, como a volta do OAuth deixa.
  def make_mercadopago_account(tenant, modality: "pix", environment: "sandbox", connected: true, config: {})
    base = { "boleto" => { "beneficiary_name" => "Escola Alfa Ltda", "beneficiary_document" => "41755489000155" }, "card" => { "max_installments" => 6 } }.fetch(modality, {})
    account = Payments::AccountManager.new(users(:joana)).create(tenant: tenant, account_code: "0001-99999-0", modality: modality, provider: "mercadopago", environment: environment,
                                                                 nickname: "Mercado Pago #{modality} #{SecureRandom.hex(2)}", values: { config: base.merge(config) })
    return account unless connected

    account.update!(secrets: account.secrets.merge("access_token" => "APP_USR-VENDEDOR", "refresh_token" => "TG-RENOVA"),
                    config: account.config.merge("connection_state" => "connected", "connected_at" => Time.current.iso8601, "token_expires_at" => 90.days.from_now.iso8601,
                                                 "connection_account_id" => SELLER, "connection_public_key" => "APP_USR-chave-publica"))
    account
  end

  # Linha digitável válida (dígitos conferidos) de um banco qualquer, com o fator do vencimento e o valor dados.
  def mercadopago_line(due_on, amount_cents, bank: "033")
    n43 = "#{bank}9#{Payments::Febraban.due_factor(due_on).to_s.rjust(4, '0')}#{amount_cents.to_s.rjust(10, '0')}#{'9' * 7}#{'1' * 18}"
    barcode = "#{n43[0, 4]}#{Payments::Febraban.barcode_check_digit(n43)}#{n43[4..]}"
    Payments::Febraban.digitable_from_barcode(barcode)
  end

  # Pedido como a API Orders o devolve, com uma transação do meio dado.
  def mercadopago_order(kind: "pix", status: "action_required", amount_cents: 125_000, line: nil, refunds: [], status_detail: nil, installments: nil)
    method = case kind
    when "pix" then { "id" => "pix", "type" => "bank_transfer", "qr_code" => "00020126580014br.gov.bcb.pix0136mercadopago5204000053039865802BR", "qr_code_base64" => "", "ticket_url" => "https://www.mercadopago.com.br/payments/1/ticket" }
    when "boleto" then { "id" => "boleto", "type" => "ticket", "digitable_line" => line, "barcode_content" => "", "reference" => "1234567890", "financial_institution" => "Banco Santander",
                         "ticket_url" => "https://www.mercadopago.com.br/payments/1/ticket" }
    else { "id" => "visa", "type" => "credit_card", "installments" => installments || 1 }
    end
    { "id" => ORDER_ID, "status" => status, "status_detail" => status_detail, "external_reference" => "REF", "total_amount" => format("%.2f", amount_cents / 100.0),
      "transactions" => { "payments" => [ { "id" => PAYMENT_ID, "amount" => format("%.2f", amount_cents / 100.0), "status" => status, "status_detail" => status_detail,
                                            "payment_method" => method } ], "refunds" => refunds } }
  end

  # Assinatura do aviso, como a página de notificações descreve.
  def mercadopago_signature(data_id, request_id: "req-1", ts: "1731590000000", secret: "segredo-webhook")
    # O `data.id` vai em minúsculas quando é só letras e números (página de notificações).
    manifest = "id:#{data_id.match?(/\A[[:alnum:]]+\z/) ? data_id.downcase : data_id};request-id:#{request_id};ts:#{ts};"
    { "x-signature" => "ts=#{ts},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, manifest)}", "x-request-id" => request_id }
  end
end
