# Planilhas e registros de pagamentos para os testes: cliente, contrato e título prontos, e as linhas dos CSVs (03, revisão 12: meio, fornecedor e identificador).
module PaymentsHelper
  PAYMENT_HEADER = %w[fornecedor conta identificador documento titulo data_pagamento valor meio estado_final].freeze
  REVERSAL_HEADER = %w[meio fornecedor conta identificador_pagamento identificador_estorno data_estorno valor motivo].freeze
  # O fornecedor das linhas de teste: como a planilha escreve e a chave que entra na identidade do pagamento.
  PROVIDER = "Itaú".freeze
  PROVIDER_KEY = "itau".freeze
  ACCOUNT = "0341-12345-6".freeze
  MARIA = "529.982.247-25".freeze
  JOAO = "390.533.447-05".freeze

  def brl_date(days_ago = 1) = (Date.current - days_ago).strftime("%d/%m/%Y")

  def payment_line(overrides = {})
    { "fornecedor" => PROVIDER, "conta" => ACCOUNT, "identificador" => "PIX-1", "documento" => MARIA, "titulo" => "NF-1", "data_pagamento" => brl_date(1), "valor" => "1.000,00",
      "meio" => "pix" }.merge(overrides.transform_keys(&:to_s))
  end

  def reversal_line(overrides = {})
    { "meio" => "pix", "fornecedor" => PROVIDER, "conta" => ACCOUNT, "identificador_pagamento" => "PIX-1", "identificador_estorno" => "EST-1", "data_estorno" => brl_date(0), "valor" => "300,00",
      "motivo" => "contestação" }.merge(overrides.transform_keys(&:to_s))
  end

  # Os atributos de "como foi pago" de um pagamento criado direto no banco.
  def paid_via(method = "pix", provider: PROVIDER, account: ACCOUNT)
    { payment_method: method, provider: PaymentProvider.key(provider), provider_name: provider, account_key: PaymentProvider.account_key(account), account_code: account }
  end

  # Cliente com um contrato e um título; devolve o título.
  def make_bill(tenant, number: "NF-1", amount_cents: 100_000, document: MARIA, contract_code: "CT-1", status: :active, due: Date.current - 30, name: "Maria Souza")
    customer = Customer.find_or_create_by!(tenant: tenant, document: Document.normalize(document)) { |record| record.name = name }
    contract = Contract.find_or_create_by!(tenant: tenant, code: contract_code)
    ContractCustomer.find_or_create_by!(contract: contract, customer: customer)
    Bill.create!(tenant: tenant, contract: contract, customer: customer, number: number, due_date: due, amount_cents: amount_cents, status: status)
  end

  # Um título novo do cliente, para servir de objeto a um instrumento ou link (16: todo instrumento cobra um título ou uma promessa).
  def bill_for(customer, amount_cents: 100_000)
    contract = customer.contracts.first || Contract.create!(tenant: customer.tenant, code: "CT-#{SecureRandom.hex(3)}").tap { |c| ContractCustomer.create!(contract: c, customer: customer) }
    Bill.create!(tenant: customer.tenant, contract: contract, customer: customer, number: "NF-#{SecureRandom.hex(4)}", due_date: Date.current - 30, amount_cents: amount_cents, status: :active)
  end

  # Envia um arquivo de pagamentos ou de estornos, confere e (opcionalmente) confirma, como a tela faria.
  def run_payments_import(lines, kind: "payments", tenant: tenants(:alfa), user: users(:joana), confirm: false)
    header = kind == "payments" ? PAYMENT_HEADER : REVERSAL_HEADER
    import = Portfolio::ImportService.new.start(tenant: tenant, user: user, file: write_csv(lines, header: header), mode: :incremental, original_name: "#{kind}.csv", kind: kind)
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
    confirm ? confirm_import(import) : import
  end

  def confirm_import(import)
    Portfolio::ImportService.new.confirm(import)
    perform_enqueued_jobs(only: ConfirmImportJob)
    import.reload
  end

  # Usuário novo, com vínculo e um perfil de permissões escolhidas, em um credor.
  def make_user(tenant, permissions, email: "u#{SecureRandom.hex(3)}@exemplo.com.br")
    user = User.create!(name: "Usuário de teste", email_address: email, password: "senha-de-teste-1")
    profile = Profile.create!(tenant: tenant, name: "Perfil #{SecureRandom.hex(3)}", permissions: ([ "view_portfolio" ] + permissions).uniq)
    Membership.create!(user: user, tenant: tenant, profile: profile)
    user
  end
end
