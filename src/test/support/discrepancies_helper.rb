# Cargas de carteira e títulos com pagamento para os testes da carteira revista (05).
module DiscrepanciesHelper
  # Linha de carga do cliente e do contrato que `make_bill` cria (Maria, CT-1).
  def bill_line(number, value, overrides = {})
    csv_line({ "documento" => PaymentsHelper::MARIA, "nome" => "Maria Souza", "contrato" => "CT-1", "titulo" => number, "valor" => value }.merge(overrides.transform_keys(&:to_s)))
  end

  # Envia, confere e (opcionalmente) confirma uma carga de carteira, como a tela faria.
  def run_portfolio_import(lines, tenant: tenants(:alfa), user: users(:joana), mode: :incremental, confirm: false, header: CsvHelper::HEADER)
    import = Portfolio::ImportService.new.start(tenant: tenant, user: user, file: write_csv(lines, header: header), mode: mode, original_name: "carteira.csv")
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
    return import unless confirm

    Portfolio::ImportService.new.confirm(import, by: user)
    perform_enqueued_jobs(only: ConfirmImportJob)
    import.reload
  end

  # Título de Maria com um pagamento aplicado (o canal é criado se faltar); devolve o título recarregado.
  def paid_bill(tenant: tenants(:alfa), number: "NF-1024/3", amount_cents: 100_000, paid_cents: 40_000, **options)
    make_channel(tenant) unless PaymentChannel.exists?(tenant: tenant, code: PaymentsHelper::CHANNEL_CODE)
    bill = make_bill(tenant, number: number, amount_cents: amount_cents, **options)
    pay_bill(bill, paid_cents) if paid_cents.positive?
    bill.reload
  end

  def pay_bill(bill, cents, id: "PIX-#{SecureRandom.hex(3)}")
    run_payments_import([ payment_line("identificador" => id, "documento" => bill.customer.document, "titulo" => bill.number, "valor" => Money.format(cents)) ],
                        tenant: bill.tenant, confirm: true)
    id
  end

  def set_discrepancy_policy(policy, tenant: tenants(:alfa)) = tenant.setting.update!(discrepancy_policy: policy)
end
