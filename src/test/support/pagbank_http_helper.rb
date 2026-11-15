# O PagBank nos testes (12, revisão 5): o mesmo cliente HTTP falso da Efí, com respostas gravadas à mão a partir dos exemplos do portal, e a aplicação da
# instalação no Connect pelas variáveis de ambiente de teste. Nenhum teste chama o PagBank.
module PagbankHttpHelper
  ORDER_ID = "ORDE_F87334AC-BB8B-42E2-AA85-8579F70AA328".freeze
  CHARGE_ID = "CHAR_67C5D9D3-AF9B-4D7D-A6E2-9F5E0D9C6A11".freeze
  APP_ENV = { "CRM_CONNECT_PAGBANK_SANDBOX_CLIENT_ID" => "app-crm-sandbox", "CRM_CONNECT_PAGBANK_SANDBOX_CLIENT_SECRET" => "segredo-app-sandbox",
              "CRM_CONNECT_PAGBANK_SANDBOX_PLATFORM_TOKEN" => "token-plataforma-sandbox",
              "CRM_CONNECT_PAGBANK_PRODUCTION_CLIENT_ID" => "app-crm-producao", "CRM_CONNECT_PAGBANK_PRODUCTION_CLIENT_SECRET" => "segredo-app-producao" }.freeze

  def use_pagbank_client(client)
    Payments::Providers::Pagbank.http_client = client
    client
  end

  def pagbank_client = EfiHttpHelper::FakeClient.new

  # A aplicação do Connect da instalação existe durante o bloco (ou o teste inteiro, sem bloco: o `teardown` do helper limpa).
  def with_pagbank_app
    APP_ENV.each { |key, value| ENV[key] = value }
    return unless block_given?

    begin
      yield
    ensure
      APP_ENV.each_key { |key| ENV.delete(key) }
    end
  end

  def without_pagbank_app = APP_ENV.each_key { |key| ENV.delete(key) }

  # Integração PagBank criada como o gestor a cria (chave da URL gerada) e, se `connected`, já conectada, com o token valendo por uma hora.
  def make_pagbank_account(tenant, modality: "pix", environment: "sandbox", connected: true, config: {}, expires_at: 1.hour.from_now)
    base = { "boleto" => { "fine_percent" => 2, "interest_percent" => 1, "write_off_days" => 30, "message" => "Não receber depois de 30 dias do vencimento." },
             "card" => { "max_installments" => 6, "interest_free_installments" => 3, "soft_descriptor" => "Escola Alfa" } }.fetch(modality, {})
    account = Payments::AccountManager.new(users(:joana)).create(tenant: tenant, account_code: "0001-99999-0", modality: modality, provider: "pagbank", environment: environment,
                                                                 nickname: "PagBank #{modality} #{SecureRandom.hex(2)}", values: { config: base.merge(config) })
    return account unless connected

    account.update!(secrets: account.secrets.merge("access_token" => "TOKEN-VENDEDOR-1", "refresh_token" => "RENOVA-1"),
                    config: account.config.merge("connection_state" => "connected", "connected_at" => Time.current.iso8601, "token_expires_at" => expires_at&.iso8601).compact)
    account
  end

  # Pedido como o PagBank o devolve (formato da página do objeto do pedido), com uma cobrança no estado dado.
  def pagbank_order(kind: "pix", status: nil, paid: nil, refunded: 0, amount: 125_000, reference: "REF", extra_charge: {})
    order = { "id" => ORDER_ID, "reference_id" => reference, "created_at" => "2026-11-14T10:00:00-03:00", "customer" => { "name" => "Maria Souza", "tax_id" => "52998224725" } }
    if kind == "pix"
      order["qr_codes"] = [ { "id" => "QRCO_1", "text" => "00020101021226850014br.gov.bcb.pix2563api.pagseguro.com/pix/v2/1234", "expiration_date" => "2026-11-30T23:59:59-03:00",
                              "amount" => { "value" => amount }, "links" => [ { "rel" => "QRCODE.PNG", "href" => "https://api.pagseguro.com/qrcode/QRCO_1/png", "media" => "image/png" } ] } ]
    end
    return order unless status

    charge = { "id" => CHARGE_ID, "reference_id" => reference, "status" => status, "amount" => { "value" => amount, "currency" => "BRL", "summary" => { "total" => amount, "paid" => paid.to_i, "refunded" => refunded } } }
    charge["paid_at"] = "2026-11-14T10:05:00-03:00" if paid
    if kind == "boleto"
      charge["payment_method"] = { "type" => "BOLETO", "boleto" => { "id" => "BOLE_1", "barcode" => "03399853012970000024227020901016278150000125000",
                                                                       "formatted_barcode" => "03399.85301 29700.000242 27020.901016 2 78150000125000", "due_date" => "2026-11-30" } }
      charge["links"] = [ { "rel" => "SELF", "href" => "https://boleto.pagseguro.com.br/BOLE_1.pdf", "media" => "application/pdf", "type" => "GET" },
                          { "rel" => "SELF", "href" => "https://boleto.pagseguro.com.br/BOLE_1.png", "media" => "image/png", "type" => "GET" } ]
    elsif kind == "pix" && paid
      charge["payment_method"] = { "type" => "PIX", "pix" => { "end_to_end_id" => "E18236120202611141005s0123456789", "holder" => { "name" => "Maria Souza", "tax_id" => "***982247**" } } }
    end
    order.merge("charges" => [ charge.deep_merge(extra_charge) ])
  end
end
